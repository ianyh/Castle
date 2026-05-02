//
//  SearchIndex.swift
//  Castle
//
//  Created by Ian Ynda-Hummel on 9/1/18.
//  Copyright © 2018 Ian Ynda-Hummel. All rights reserved.
//

import Foundation
import GRDB

struct SearchResult {
    let id: String
    let name: String
    let sheetTitle: String
    let imageURL: URL?
}

struct SearchResultSection {
    let sheetTitle: String
    let results: [SearchResult]
}

struct SearchResults {
    /// One section per priority sheet that has matches, in declared priority order. Each capped.
    let sections: [SearchResultSection]
    /// Everything from non-priority sheets, flattened and sorted by FTS rank.
    let rest: [SearchResult]

    var isEmpty: Bool { sections.isEmpty && rest.isEmpty }
}

struct RelationshipGroup {
    let sheetTitle: String
    let rowIDs: [String]
}

// FTS5 table name — lives in the shared castle.db alongside the data tables.
private let ftsTable = "search_rows"

actor SearchIndex {
    /// Sheets listed here float to the top of `search` results in declared order.
    /// Anything not in the list falls through to a single bucket sorted purely by FTS rank.
    static let prioritizedSheets: [String] = [
        "Characters",
        "Soul Breaks",
        "Hero Abilities"
    ]

    private let db: DatabaseQueue

    init(db: DatabaseQueue) {
        self.db = db
    }

    // Call beginRebuild, then indexSheet for each sheet, then commitRebuild.
    // Each sheet write is its own transaction so row objects can be freed between sheets.

    func beginRebuild() throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM \(ftsTable);")
        }
    }

    func indexSheet(title: String, rows: [(id: String, dbID: String, imageURL: String?, values: [(title: String, value: String)])]) throws {
        try db.write { db in
            let statement = try db.makeStatement(sql: """
                INSERT INTO \(ftsTable) (row_id, db_id, sheet_title, image_url, name, content)
                VALUES (?, ?, ?, ?, ?, ?);
                """
            )
            for row in rows {
                let nameValue = row.values.first(where: { $0.title.hasSuffix("Name") || $0.title == "Common Name" })?.value ?? ""
                let contentParts = row.values
                    .filter { !$0.value.isEmpty && !$0.title.isEmpty }
                    .map { "\($0.title): \($0.value)" }
                    .joined(separator: " | ")
                try statement.execute(arguments: [row.id, row.dbID, title, row.imageURL, nameValue, contentParts])
            }
        }
    }

    func commitRebuild() throws {
        try db.write { db in
            try db.execute(sql: "INSERT INTO \(ftsTable)(\(ftsTable)) VALUES ('optimize');")
        }
    }

    /// Full-text search. Priority sheets are grouped into capped sections in declared
    /// order; everything else is returned as a single flat list ordered by FTS rank.
    ///
    /// SQL is bounded: one query per priority sheet (LIMIT `perSectionLimit`) so each
    /// priority section is guaranteed its top N regardless of how dominant other sheets
    /// are, plus one query for the rest (LIMIT `restLimit`).
    func search(query: String, sheets: [String]? = nil, perSectionLimit: Int = 8, restLimit: Int = 200) throws -> SearchResults {
        guard let ftsQuery = Self.buildFTSQuery(from: query) else {
            return SearchResults(sections: [], rest: [])
        }

        let allowedSet: Set<String>? = sheets.map(Set.init)
        let priorityList: [String]
        if let allowedSet {
            priorityList = Self.prioritizedSheets.filter { allowedSet.contains($0) }
        } else {
            priorityList = Self.prioritizedSheets
        }
        let prioritySet = Set(priorityList)

        return try db.read { db in
            var sections: [SearchResultSection] = []
            for sheetTitle in priorityList {
                let rows = try Row.fetchAll(
                    db,
                    sql: """
                        SELECT row_id, name, sheet_title, image_url FROM \(ftsTable)
                        WHERE \(ftsTable) MATCH ? AND sheet_title = ?
                        ORDER BY rank
                        LIMIT ?;
                        """,
                    arguments: [ftsQuery, sheetTitle, perSectionLimit]
                )
                let results = rows.map { collectResult(from: $0) }
                if !results.isEmpty {
                    sections.append(SearchResultSection(sheetTitle: sheetTitle, results: results))
                }
            }

            // Rest = matches in non-priority sheets, optionally constrained to the caller's `sheets` filter.
            let restAllowed: Set<String>?
            if let allowedSet {
                let rest = allowedSet.subtracting(prioritySet)
                if rest.isEmpty {
                    return SearchResults(sections: sections, rest: [])
                }
                restAllowed = rest
            } else {
                restAllowed = nil
            }

            let filterClause: SQL
            if let restAllowed {
                filterClause = " AND sheet_title IN \(Array(restAllowed))"
            } else if !prioritySet.isEmpty {
                filterClause = " AND sheet_title NOT IN \(Array(prioritySet))"
            } else {
                filterClause = ""
            }

            let restQuery: SQL = """
                SELECT row_id, name, sheet_title, image_url FROM search_rows
                WHERE search_rows MATCH \(ftsQuery)\(literal: filterClause)
                ORDER BY rank LIMIT \(restLimit)
                """
            let restRows = try SQLRequest<Row>(literal: restQuery).fetchAll(db)
            let rest = restRows.map { collectResult(from: $0) }

            return SearchResults(sections: sections, rest: rest)
        }
    }

    /// Find rows matching specific dbIDs (for Specials).
    func search(dbIDs: [String], sheets: [String]? = nil) throws -> [SearchResult] {
        guard !dbIDs.isEmpty else {
            return []
        }
        return try db.read { db in
            let idPlaceholders = dbIDs.map { _ in "?" }.joined(separator: ", ")
            var sql = "SELECT row_id, name, sheet_title, image_url FROM \(ftsTable) WHERE db_id IN (\(idPlaceholders))"
            var arguments = StatementArguments(dbIDs)

            if let sheets = sheets, !sheets.isEmpty {
                let placeholders = sheets.map { _ in "?" }.joined(separator: ", ")
                sql += " AND sheet_title IN (\(placeholders))"
                arguments += StatementArguments(sheets)
            }
            sql += ";"

            return try Row.fetchAll(db, sql: sql, arguments: arguments).map { collectResult(from: $0) }
        }
    }

    /// Search for Effects content matching a status query string (for Specials effects lookup).
    func searchEffects(matchQuery: String, sheets: [String]) throws -> [SearchResult] {
        guard !matchQuery.isEmpty else {
            return []
        }
        return try db.read { db in
            let placeholders = sheets.map { _ in "?" }.joined(separator: ", ")
            let sql = """
                SELECT row_id, name, sheet_title, image_url
                FROM \(ftsTable)
                WHERE \(ftsTable) MATCH ?
                AND sheet_title IN (\(placeholders))
                ORDER BY rank;
                """
            var arguments: StatementArguments = [matchQuery]
            arguments += StatementArguments(sheets)
            return try Row.fetchAll(db, sql: sql, arguments: arguments).map { collectResult(from: $0) }
        }
    }

    /// Find related rows for a given row (used in RowDetailView relationships section).
    func findRelated(rowName: String, sheetNormalizedName: String, effect: String?) throws -> [RelationshipGroup] {
        let contentQuery = "content: \"\(rowName.replacingOccurrences(of: "\"", with: "\"\""))\""
        var grouped: [String: [String]] = [:]

        let contentRows = try db.read { db in
            try Row.fetchAll(db, sql: "SELECT row_id, sheet_title FROM \(ftsTable) WHERE \(ftsTable) MATCH ?;", arguments: [contentQuery])
        }
        for row in contentRows {
            let id: String = row["row_id"]
            let sheetTitle: String = row["sheet_title"]
            grouped[sheetTitle, default: []].append(id)
        }

        if let effect = effect {
            let statusRegex = try NSRegularExpression(pattern: "\\[(.+?)\\]")
            for match in statusRegex.matches(in: effect, range: NSRange(effect.startIndex..., in: effect)) {
                guard let range = Range(match.range(at: 1), in: effect) else {
                    continue
                }
                let status = String(effect[range])
                let statusResults = try searchByName(status)
                for result in statusResults {
                    grouped[result.sheetTitle, default: []].append(result.id)
                }
            }
        }

        return grouped
            .map { RelationshipGroup(sheetTitle: $0.key, rowIDs: $0.value) }
            .sorted { $0.sheetTitle < $1.sheetTitle }
    }

    private func searchByName(_ name: String) throws -> [(id: String, sheetTitle: String)] {
        return try db.read { db in
            try Row.fetchAll(db, sql: "SELECT row_id, sheet_title FROM \(ftsTable) WHERE name = ?;", arguments: [name])
                .map { (id: $0["row_id"] as String, sheetTitle: $0["sheet_title"] as String) }
        }
    }

    /// Splits a free-text query on whitespace and turns each token into a quoted FTS5
    /// prefix term, joined by spaces (implicit AND). Returns nil if no usable tokens.
    /// Example: "cloud dasb" → `"cloud"* "dasb"*` — matches rows containing both tokens
    /// in any order.
    static func buildFTSQuery(from query: String) -> String? {
        let tokens = query
            .split(whereSeparator: { $0.isWhitespace })
            .map { $0.replacingOccurrences(of: "\"", with: "\"\"") }
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else {
            return nil
        }
        return tokens.map { "\"\($0)\"*" }.joined(separator: " ")
    }

    private func collectResult(from row: Row) -> SearchResult {
        SearchResult(
            id: row["row_id"],
            name: (row["name"] as String?) ?? "",
            sheetTitle: row["sheet_title"],
            imageURL: (row["image_url"] as String?).flatMap { URL(string: $0) }
        )
    }
}
