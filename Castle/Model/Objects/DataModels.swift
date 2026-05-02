//
//  DataModels.swift
//  Castle
//
//  Created by Ian Ynda-Hummel on 9/1/18.
//  Copyright © 2018 Ian Ynda-Hummel. All rights reserved.
//

import Foundation
import GRDB

// MARK: - Embedded value types (stored as JSON blobs inside their parent rows)

struct SpreadsheetColumn: Codable, Hashable, Identifiable {
    var id: String { key }
    var key: String
    var isColumnFrozen: Bool
    var title: String
}

struct RowValue: Codable, Hashable, Identifiable {
    var id: String
    var columnKey: String?
    var columnTitle: String
    var isColumnFrozen: Bool
    var title: String
    var value: String
    var imageURL: String?
}

// MARK: - GRDB record types

struct Spreadsheet: Identifiable {
    var id: String { title }
    var title: String
    var columns: [SpreadsheetColumn]

    init(title: String, columns: [SpreadsheetColumn] = []) {
        self.title = title
        self.columns = columns
    }

    var normalizedName: String {
        title.hasSuffix("s") ? String(title.dropLast()) : title
    }

    var frozenColumns: [SpreadsheetColumn] {
        columns.filter { $0.isColumnFrozen }
    }
}

extension Spreadsheet: FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "spreadsheets" }

    init(row: Row) throws {
        title = row["title"]
        let data: Data = row["columns_json"]
        columns = (try? JSONDecoder().decode([SpreadsheetColumn].self, from: data)) ?? []
    }

    func encode(to container: inout PersistenceContainer) throws {
        container["title"] = title
        container["columns_json"] = try JSONEncoder().encode(columns)
    }
}

struct SpreadsheetRow: Identifiable {
    var id: String
    var dbID: String
    var spreadsheetTitle: String
    var values: [RowValue]

    init(id: String, dbID: String, spreadsheetTitle: String, values: [RowValue] = []) {
        self.id = id
        self.dbID = dbID
        self.spreadsheetTitle = spreadsheetTitle
        self.values = values
    }

    var normalizedName: String? {
        values.first(where: { $0.columnTitle.hasSuffix("Name") })?.value
    }

    var effect: String? {
        values.first(where: { $0.columnTitle == "Effects" })?.value
    }
}

extension SpreadsheetRow: FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "spreadsheet_rows" }

    init(row: Row) throws {
        id = row["id"]
        dbID = row["db_id"]
        spreadsheetTitle = row["spreadsheet_title"]
        let data: Data = row["values_json"]
        values = (try? JSONDecoder().decode([RowValue].self, from: data)) ?? []
    }

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["db_id"] = dbID
        container["spreadsheet_title"] = spreadsheetTitle
        container["values_json"] = try JSONEncoder().encode(values)
    }
}

struct LastUpdate: FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "last_update" }
    var id: String
    var date: Date

    init(date: Date) {
        self.id = "singleton"
        self.date = date
    }

    init(row: Row) throws {
        id = row["id"]
        date = Date(timeIntervalSince1970: row["date"])
    }

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["date"] = date.timeIntervalSince1970
    }
}
