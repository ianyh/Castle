//
//  AppStore+Preview.swift
//  Castle
//
//  Preview-only factory. Builds an in-memory GRDB store with a small seed dataset
//  so SwiftUI previews can render against realistic data.
//

#if DEBUG
import Foundation
import GRDB

extension AppStore {
    @MainActor
    static var preview: AppStore {
        let queue: DatabaseQueue
        do {
            queue = try DatabaseQueue()
            try migrator.migrate(queue)
            try seed(into: queue)
        } catch {
            fatalError("Preview store setup failed: \(error)")
        }
        let sheets = (try? queue.read { try Spreadsheet.order(Column("title")).fetchAll($0) }) ?? []
        let lastUpdate = (try? queue.read { try LastUpdate.fetchOne($0)?.date }) ?? nil
        return AppStore(db: queue, sheets: sheets, lastUpdate: lastUpdate)
    }

    private static func seed(into queue: DatabaseQueue) throws {
        let sheets = [
            Spreadsheet(title: "Characters", columns: [
                SpreadsheetColumn(key: "Characters-Name", isColumnFrozen: true, title: "Name"),
                SpreadsheetColumn(key: "Characters-Realm", isColumnFrozen: true, title: "Realm"),
                SpreadsheetColumn(key: "Characters-Notes", isColumnFrozen: false, title: "Notes")
            ]),
            Spreadsheet(title: "Soul Breaks", columns: [
                SpreadsheetColumn(key: "SoulBreaks-Name", isColumnFrozen: true, title: "Name"),
                SpreadsheetColumn(key: "SoulBreaks-Character", isColumnFrozen: true, title: "Character"),
                SpreadsheetColumn(key: "SoulBreaks-Effects", isColumnFrozen: true, title: "Effects")
            ]),
            Spreadsheet(title: "Status", columns: [
                SpreadsheetColumn(key: "Status-Name", isColumnFrozen: true, title: "Name"),
                SpreadsheetColumn(key: "Status-Effects", isColumnFrozen: true, title: "Effects")
            ])
        ]

        let rows: [SpreadsheetRow] = [
            previewRow(id: "Characters-00001", dbID: "Characters-1", sheet: "Characters", values: [
                ("Name", "Cloud", true),
                ("Realm", "VII", true),
                ("Notes", "Wields the Buster Sword.", false)
            ]),
            previewRow(id: "Characters-00002", dbID: "Characters-2", sheet: "Characters", values: [
                ("Name", "Tifa", true),
                ("Realm", "VII", true),
                ("Notes", "Martial artist.", false)
            ]),
            previewRow(id: "Soul Breaks-00001", dbID: "SoulBreaks-1", sheet: "Soul Breaks", values: [
                ("Name", "Omnislash", true),
                ("Character", "Cloud", true),
                ("Effects", "Eight physical strikes.", true)
            ]),
            previewRow(id: "Soul Breaks-00002", dbID: "SoulBreaks-2", sheet: "Soul Breaks", values: [
                ("Name", "Final Heaven", true),
                ("Character", "Tifa", true),
                ("Effects", "Massive single-target damage.", true)
            ]),
            previewRow(id: "Status-00001", dbID: "Status-1", sheet: "Status", values: [
                ("Name", "Burst Mode", true),
                ("Effects", "Grants access to burst commands.", true)
            ])
        ]

        try queue.write { db in
            for sheet in sheets {
                try sheet.insert(db, onConflict: .replace)
            }
            for row in rows {
                try row.insert(db, onConflict: .replace)
            }
            try LastUpdate(date: Date()).insert(db, onConflict: .replace)
        }

        let grouped = Dictionary(grouping: rows, by: \.spreadsheetTitle)
        for (sheetTitle, sheetRows) in grouped {
            let indexRows = sheetRows.map { row in
                (
                    id: row.id,
                    dbID: row.dbID,
                    imageURL: row.values.first(where: { $0.imageURL != nil })?.imageURL,
                    values: row.values.map { (title: $0.title, value: $0.value) }
                )
            }
            try indexSheetSync(queue: queue, sheetTitle: sheetTitle, rows: indexRows)
        }
    }

    private static func indexSheetSync(
        queue: DatabaseQueue,
        sheetTitle: String,
        rows: [(id: String, dbID: String, imageURL: String?, values: [(title: String, value: String)])]
    ) throws {
        try queue.write { db in
            let stmt = try db.makeStatement(sql: """
                INSERT INTO search_rows (row_id, db_id, sheet_title, image_url, name, content)
                VALUES (?, ?, ?, ?, ?, ?);
                """)
            for row in rows {
                let nameValue = row.values.first(where: { $0.title.hasSuffix("Name") || $0.title == "Common Name" })?.value ?? ""
                let contentParts = row.values
                    .filter { !$0.value.isEmpty && !$0.title.isEmpty }
                    .map { "\($0.title): \($0.value)" }
                    .joined(separator: " | ")
                try stmt.execute(arguments: [row.id, row.dbID, sheetTitle, row.imageURL, nameValue, contentParts])
            }
        }
    }

    private static func previewRow(
        id: String,
        dbID: String,
        sheet: String,
        values: [(title: String, value: String, frozen: Bool)]
    ) -> SpreadsheetRow {
        let rowValues = values.enumerated().map { idx, v in
            RowValue(
                id: "\(id)-\(String(format: "%05d", idx))",
                columnKey: "\(sheet)-\(v.title)",
                columnTitle: v.title,
                isColumnFrozen: v.frozen,
                title: v.title,
                value: v.value,
                imageURL: nil
            )
        }
        return SpreadsheetRow(id: id, dbID: dbID, spreadsheetTitle: sheet, values: rowValues)
    }
}

extension Spreadsheet {
    @MainActor
    static var preview: Spreadsheet {
        AppStore.preview.sheets.first(where: { $0.title == "Characters" })!
    }
}

extension SpreadsheetRow {
    @MainActor
    static var preview: SpreadsheetRow {
        let store = AppStore.preview
        return (try? store.db.read {
            try SpreadsheetRow.fetchOne($0, key: "Characters-00001")
        }) ?? SpreadsheetRow(id: "", dbID: "", spreadsheetTitle: "")
    }
}
#endif
