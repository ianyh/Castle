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

    let db: DatabaseQueue
    let client: SpreadsheetsClient
    let searchIndex: SearchIndex

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
