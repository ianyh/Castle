//
//  CastleTests.swift
//  CastleTests
//
//  Created by Ian Ynda-Hummel on 9/19/17.
//  Copyright © 2017 Ian Ynda-Hummel. All rights reserved.
//

import GRDB
import XCTest
@testable import Castle

final class CastleTests: XCTestCase {
    private func makeQueue() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try AppStore.migrator.migrate(queue)
        return queue
    }

    // MARK: - Record round-trips

    func testSpreadsheetRoundTrip() throws {
        let queue = try makeQueue()
        let columns = [
            SpreadsheetColumn(key: "1-Name", isColumnFrozen: true, title: "Name"),
            SpreadsheetColumn(key: "1-Effects", isColumnFrozen: true, title: "Effects"),
            SpreadsheetColumn(key: "1-Notes", isColumnFrozen: false, title: "Notes")
        ]
        let sheet = Spreadsheet(title: "Characters", columns: columns)

        try queue.write { try sheet.insert($0) }

        let fetched = try queue.read { try Spreadsheet.fetchOne($0, key: "Characters") }
        let unwrapped = try XCTUnwrap(fetched)
        XCTAssertEqual(unwrapped.title, "Characters")
        XCTAssertEqual(unwrapped.columns, columns)
        XCTAssertEqual(unwrapped.frozenColumns.map(\.title), ["Name", "Effects"])
    }

    func testSpreadsheetRowRoundTrip() throws {
        let queue = try makeQueue()
        let values = [
            RowValue(id: "Characters-00001-00000", columnKey: "1-Name", columnTitle: "Name",
                     isColumnFrozen: true, title: "Name", value: "Cloud", imageURL: nil),
            RowValue(id: "Characters-00001-00001", columnKey: "1-Img", columnTitle: "Img",
                     isColumnFrozen: false, title: "Img", value: "", imageURL: "https://example.com/cloud.png")
        ]
        let row = SpreadsheetRow(id: "Characters-00001", dbID: "Characters-1",
                                 spreadsheetTitle: "Characters", values: values)

        try queue.write { try row.insert($0) }

        let fetched = try queue.read {
            try SpreadsheetRow.fetchOne($0, key: "Characters-00001")
        }
        let unwrapped = try XCTUnwrap(fetched)
        XCTAssertEqual(unwrapped.id, "Characters-00001")
        XCTAssertEqual(unwrapped.dbID, "Characters-1")
        XCTAssertEqual(unwrapped.spreadsheetTitle, "Characters")
        XCTAssertEqual(unwrapped.values, values)
        XCTAssertEqual(unwrapped.normalizedName, "Cloud")
    }

    // MARK: - FTS5 search

    func testFTS5BasicSearch() async throws {
        let queue = try makeQueue()
        let index = SearchIndex(db: queue)

        try await index.beginRebuild()
        try await index.indexSheet(title: "Characters", rows: [
            (id: "Characters-00001", dbID: "Characters-1", imageURL: nil,
             values: [(title: "Name", value: "Cloud"), (title: "Notes", value: "wields buster sword")])
        ])
        try await index.indexSheet(title: "Soul Breaks", rows: [
            (id: "Soul Breaks-00001", dbID: "SB-1", imageURL: nil,
             values: [(title: "Name", value: "Omnislash"), (title: "Effects", value: "eight strikes")])
        ])
        try await index.commitRebuild()

        let results = try await index.search(query: "buster")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.id, "Characters-00001")
        XCTAssertEqual(results.first?.sheetTitle, "Characters")
    }

    func testFTS5SheetFilter() async throws {
        let queue = try makeQueue()
        let index = SearchIndex(db: queue)

        try await index.beginRebuild()
        try await index.indexSheet(title: "Characters", rows: [
            (id: "Characters-00001", dbID: "Characters-1", imageURL: nil,
             values: [(title: "Name", value: "Cloud"), (title: "Notes", value: "limit break ready")])
        ])
        try await index.indexSheet(title: "Soul Breaks", rows: [
            (id: "Soul Breaks-00001", dbID: "SB-1", imageURL: nil,
             values: [(title: "Name", value: "Omnislash"), (title: "Effects", value: "limit break")])
        ])
        try await index.commitRebuild()

        let unfiltered = try await index.search(query: "limit")
        XCTAssertEqual(unfiltered.count, 2)

        let filtered = try await index.search(query: "limit", sheets: ["Soul Breaks"])
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.sheetTitle, "Soul Breaks")
    }
}
