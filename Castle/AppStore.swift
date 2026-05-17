//
//  AppStore.swift
//  Castle
//
//  Created by Ian Ynda-Hummel on 9/1/18.
//  Copyright © 2018 Ian Ynda-Hummel. All rights reserved.
//

import Foundation
import GRDB
import Kingfisher
import Observation

@Observable
@MainActor
final class AppStore {
    private(set) var sheets: [Spreadsheet] = []
    private(set) var lastUpdate: Date?
    private(set) var isSyncing = false
    private(set) var syncError: Error?
    private(set) var recentSearchRows: [SpreadsheetRow] = []

    let db: DatabaseQueue
    let client: SpreadsheetsClient
    let searchIndex: SearchIndex

    private static let recentRowsCap = 20

    init(db: DatabaseQueue, sheets: [Spreadsheet] = [], lastUpdate: Date? = nil) {
        self.db = db
        self.searchIndex = SearchIndex(db: db)
        self.client = SpreadsheetsClient(db: db)
        self.sheets = sheets
        self.lastUpdate = lastUpdate
    }

    // MARK: - Database setup

    nonisolated static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_create_tables") { db in
            try db.create(table: "spreadsheets", ifNotExists: true) { t in
                t.column("title", .text).primaryKey()
                t.column("columns_json", .blob).notNull()
            }
            try db.create(table: "spreadsheet_rows", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("db_id", .text).notNull()
                t.column("spreadsheet_title", .text).notNull().indexed()
                t.column("values_json", .blob).notNull()
            }
            try db.create(table: "last_update", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("date", .double).notNull()
            }
            try db.create(virtualTable: "search_rows", ifNotExists: true, using: FTS5()) { t in
                t.column("row_id").notIndexed()
                t.column("db_id").notIndexed()
                t.column("sheet_title").notIndexed()
                t.column("image_url").notIndexed()
                t.column("name")
                t.column("content")
            }
        }
        migrator.registerMigration("v2_create_row_values") { db in
            // Normalized per-cell table used for exact-match cross-sheet lookups
            // (RowDetailView's Relationships section). Independent of FTS5 — this is
            // structured data, not full-text-indexed.
            try db.create(table: "row_values", ifNotExists: true) { t in
                t.column("row_id", .text).notNull()
                t.column("sheet_title", .text).notNull()
                t.column("column_title", .text).notNull()
                t.column("value", .text).notNull()
                t.primaryKey(["row_id", "column_title"])
            }
            try db.create(index: "idx_row_values_value", on: "row_values", columns: ["value"])
            try db.create(index: "idx_row_values_sheet_value", on: "row_values", columns: ["sheet_title", "value"])
        }
        migrator.registerMigration("v3_create_character_aliases") { db in
            // Search query shorthands pulled from the upstream Discord-bot alias file
            // during sync. Read by SearchIndex.search to canonicalize user queries.
            try db.create(table: "character_aliases", ifNotExists: true) { t in
                t.column("alias", .text).primaryKey()
                t.column("canonical", .text).notNull()
            }
        }
        migrator.registerMigration("v4_create_recent_rows") { db in
            // Recently-viewed search results — surfaces under the search field as
            // `.searchSuggestions` when the query is empty. Capped to 20 by LRU at
            // write time. Joined back to spreadsheet_rows for display data so stale
            // recents (rows removed by sync) drop out naturally.
            try db.create(table: "recent_rows", ifNotExists: true) { t in
                t.column("row_id", .text).primaryKey()
                t.column("sheet_title", .text).notNull()
                t.column("last_viewed_at", .double).notNull()
            }
            try db.create(index: "idx_recent_rows_viewed", on: "recent_rows", columns: ["last_viewed_at"])
        }
        return migrator
    }

    nonisolated static func makeDatabase() throws -> DatabaseQueue {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Castle")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let queue = try DatabaseQueue(path: dir.appendingPathComponent("castle.db").path)
        try migrator.migrate(queue)
        return queue
    }

    // MARK: - State loading

    func loadState() async {
        do {
            sheets = try await db.read { try Spreadsheet.order(Column("title")).fetchAll($0) }
            lastUpdate = try await db.read { try LastUpdate.fetchOne($0)?.date }
        } catch {
            print("Failed to load state: \(error)")
        }
        await loadRecentSearchRows()
    }

    // MARK: - Recent search rows

    /**
     Records a tap on a search result. Upserts `(rowID, sheetTitle, now)` into `recent_rows`, prunes anything past the LRU cap, then reloads `recentSearchRows` so observers (the search suggestion list) see the new top. Called only by `SearchView` — relationship-section taps and other navigation deliberately don't bump recency.
     */
    func recordSearchTap(rowID: String, sheetTitle: String) async {
        let now = Date().timeIntervalSince1970
        do {
            try await db.write { db in
                try db.execute(sql: """
                    INSERT INTO recent_rows (row_id, sheet_title, last_viewed_at) VALUES (?, ?, ?)
                    ON CONFLICT(row_id) DO UPDATE SET
                        sheet_title = excluded.sheet_title,
                        last_viewed_at = excluded.last_viewed_at;
                    """, arguments: [rowID, sheetTitle, now])
                try db.execute(sql: """
                    DELETE FROM recent_rows WHERE row_id NOT IN (
                        SELECT row_id FROM recent_rows ORDER BY last_viewed_at DESC LIMIT ?
                    );
                    """, arguments: [Self.recentRowsCap])
            }
        } catch {
            print("recordSearchTap failed: \(error)")
        }
        await loadRecentSearchRows()
    }

    func loadRecentSearchRows() async {
        do {
            recentSearchRows = try await db.read { db in
                try SpreadsheetRow.fetchAll(
                    db,
                    sql: """
                        SELECT sr.* FROM recent_rows rr
                        INNER JOIN spreadsheet_rows sr ON sr.id = rr.row_id
                        ORDER BY rr.last_viewed_at DESC
                        LIMIT ?;
                        """,
                    arguments: [Self.recentRowsCap]
                )
            }
        } catch {
            print("loadRecentSearchRows failed: \(error)")
        }
    }

    // MARK: - Sync

    func sync() async {
        isSyncing = true
        syncError = nil
        do {
            try await client.sync(searchIndex: searchIndex)
            await loadState()
        } catch {
            syncError = error
        }
        isSyncing = false
    }

    // MARK: - Image cache

    func preloadImages() -> AsyncThrowingStream<String, Error> {
        client.preloadImages()
    }

    func clearImageCache() {
        client.clearImageCache()
    }

    // MARK: - Data queries

    func fetchRows(for sheetTitle: String) async throws -> [SpreadsheetRow] {
        try await db.read { db in
            try SpreadsheetRow.fetchAll(
                db,
                sql: "SELECT * FROM spreadsheet_rows WHERE spreadsheet_title = ? ORDER BY id",
                arguments: [sheetTitle]
            )
        }
    }

    func fetchRows(ids: [String]) async throws -> [SpreadsheetRow] {
        guard !ids.isEmpty else { return [] }
        return try await db.read { db in
            let placeholders = ids.map { _ in "?" }.joined(separator: ", ")
            return try SpreadsheetRow.fetchAll(
                db,
                sql: "SELECT * FROM spreadsheet_rows WHERE id IN (\(placeholders)) ORDER BY id",
                arguments: StatementArguments(ids)
            )
        }
    }

    func fetchSpreadsheet(title: String) async throws -> Spreadsheet? {
        try await db.read { db in
            try Spreadsheet.fetchOne(
                db,
                sql: "SELECT * FROM spreadsheets WHERE title = ?",
                arguments: [title]
            )
        }
    }
}
