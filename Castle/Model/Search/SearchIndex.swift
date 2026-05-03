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

    /**
     Tier-shorthand definition. Each tier may have multiple aliases; e.g. `?zsb`, `?uasb`, `?z`, `?ua` all mean the same thing. The `canonical` form is what we substitute into the FTS query so short aliases like `z` don't over-match (a wildcard prefix on `z` would hit Zell, Zidane, zone…).
     */
    private struct Tier {
        let aliases: Set<String>
        let canonical: String
        let sheet: String
    }

    private static let tiers: [Tier] = [
        Tier(aliases: ["zsb", "uasb", "z", "ua"], canonical: "zsb", sheet: "Soul Breaks"),
        Tier(aliases: ["sb"], canonical: "sb", sheet: "Soul Breaks"),
        Tier(aliases: ["ssb"], canonical: "ssb", sheet: "Soul Breaks"),
        Tier(aliases: ["burst"], canonical: "bsb", sheet: "Soul Breaks"),
        Tier(aliases: ["osb"], canonical: "osb", sheet: "Soul Breaks"),
        Tier(aliases: ["usb"], canonical: "usb", sheet: "Soul Breaks"),
        Tier(aliases: ["glint"], canonical: "glint", sheet: "Soul Breaks"),
        Tier(aliases: ["aosb"], canonical: "aosb", sheet: "Soul Breaks"),
        Tier(aliases: ["aasb", "aa"], canonical: "aasb", sheet: "Soul Breaks"),
        Tier(aliases: ["sasb", "sa"], canonical: "sasb", sheet: "Soul Breaks"),
        Tier(aliases: ["adsb"], canonical: "adsb", sheet: "Soul Breaks"),
        Tier(aliases: ["dasb", "da"], canonical: "dasb", sheet: "Soul Breaks"),
        Tier(aliases: ["lbg"], canonical: "lbg", sheet: "Soul Breaks"),
        Tier(aliases: ["casb", "ca"], canonical: "casb", sheet: "Soul Breaks"),
        Tier(aliases: ["ozsb"], canonical: "ozsb", sheet: "Soul Breaks"),
        Tier(aliases: ["masb", "ma"], canonical: "masb", sheet: "Soul Breaks"),
        Tier(aliases: ["asb"], canonical: "asb", sheet: "Soul Breaks"),
        Tier(aliases: ["lbc"], canonical: "lbc", sheet: "Soul Breaks"),
        Tier(aliases: ["lbo"], canonical: "lbo", sheet: "Soul Breaks"),
        Tier(aliases: ["csb"], canonical: "csb", sheet: "Soul Breaks"),
        Tier(aliases: ["tasb", "ta", "tact", "tactical"], canonical: "tasb", sheet: "Soul Breaks"),
        Tier(aliases: ["lbsd", "sd"], canonical: "lbsd", sheet: "Soul Breaks"),
        Tier(aliases: ["lbgs"], canonical: "lbgs", sheet: "Soul Breaks"),
        Tier(aliases: ["bsb", "b"], canonical: "buster", sheet: "Soul Breaks"),
        Tier(aliases: ["lbgs"], canonical: "lbgs", sheet: "Soul Breaks"),
        Tier(aliases: ["ha"], canonical: "ha", sheet: "Hero Abilities")
    ]

    /// Flat alias → tier lookup, derived from `tiers` once.
    private static let aliasLookup: [String: Tier] = {
        var dict: [String: Tier] = [:]
        for tier in tiers {
            for alias in tier.aliases {
                dict[alias.lowercased()] = tier
            }
        }
        return dict
    }()

    /**
     Menu-friendly grouping by sheet, listing the canonical form of each tier. Used by `SearchView`'s prefix Menu — aliases stay typing-only to avoid cluttering the menu with duplicates.
     */
    static let prefixGroups: [(sheet: String, prefixes: [String])] = {
        Dictionary(grouping: tiers, by: \.sheet)
            .map { sheet, group in
                (sheet: sheet, prefixes: group.map(\.canonical).sorted())
            }
            .sorted { $0.sheet < $1.sheet }
    }()

    /**
     Returns the sheet list mapped to the first token of `query`, or nil if the first token isn't a known tier alias. Lookup is case-insensitive.
     */
    static func sheets(matchingPrefixIn query: String) -> [String]? {
        guard let first = query.split(whereSeparator: { $0.isWhitespace }).first else {
            return nil
        }
        return aliasLookup[String(first).lowercased()].map { [$0.sheet] }
    }

    /**
     If the first token of `query` is a known alias, returns `query` with the first token replaced by the tier's canonical form. Otherwise returns `query` unchanged. This prevents short aliases (e.g. `z`) from over-matching unrelated tokens once the FTS prefix wildcard is applied.
     */
    static func canonicalize(_ query: String) -> String {
        let parts = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard let first = parts.first?.lowercased(),
              let tier = aliasLookup[first],
              tier.canonical != first else {
            return query
        }
        return ([tier.canonical] + parts.dropFirst()).joined(separator: " ")
    }

    private let db: DatabaseQueue

    init(db: DatabaseQueue) {
        self.db = db
    }

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

    /**
     Full-text search. Priority sheets are grouped into capped sections in declared order; everything else is returned as a single flat list ordered by FTS rank.
     
     SQL is bounded: one query per priority sheet (LIMIT `perSectionLimit`) so each priority section is guaranteed its top N regardless of how dominant other sheets are, plus one query for the rest (LIMIT `restLimit`).
     */
    func search(query: String, sheets: [String]? = nil, perSectionLimit: Int = 8, restLimit: Int = 200) throws -> SearchResults {
        guard let ftsQuery = Self.buildFTSQuery(from: Self.canonicalize(query)) else {
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

    /**
     Splits a free-text query on whitespace and turns each token into a quoted FTS5 prefix term, joined by spaces (implicit AND). Returns nil if no usable tokens.
     
     Example: "cloud dasb" → `"cloud"* "dasb"*` — matches rows containing both tokens in any order.
     */
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
