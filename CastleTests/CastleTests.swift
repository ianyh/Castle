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
        XCTAssertEqual(results.sections.count, 1)
        XCTAssertEqual(results.sections.first?.sheetTitle, "Characters")
        XCTAssertEqual(results.sections.first?.results.count, 1)
        XCTAssertEqual(results.sections.first?.results.first?.id, "Characters-00001")
        XCTAssertTrue(results.rest.isEmpty)
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
        XCTAssertEqual(unfiltered.sections.map(\.sheetTitle), ["Characters", "Soul Breaks"])
        XCTAssertEqual(unfiltered.sections.flatMap(\.results).count, 2)
        XCTAssertTrue(unfiltered.rest.isEmpty)

        let filtered = try await index.search(query: "limit", sheets: ["Soul Breaks"])
        XCTAssertEqual(filtered.sections.count, 1)
        XCTAssertEqual(filtered.sections.first?.sheetTitle, "Soul Breaks")
        XCTAssertEqual(filtered.sections.first?.results.count, 1)
        XCTAssertTrue(filtered.rest.isEmpty)
    }

    func testFTS5PriorityOrdering() async throws {
        let queue = try makeQueue()
        let index = SearchIndex(db: queue)

        // Build a query that matches in three sheets: two priority sheets ("Characters",
        // "Soul Breaks") and a non-priority sheet ("Other"). Confirm priority sheets
        // become headed sections in declared order and non-priority rows fall into rest.
        try await index.beginRebuild()
        try await index.indexSheet(title: "Characters", rows: [
            (id: "Characters-00001", dbID: "Characters-1", imageURL: nil,
             values: [(title: "Name", value: "Cloud"), (title: "Notes", value: "azimuth")])
        ])
        try await index.indexSheet(title: "Soul Breaks", rows: [
            (id: "Soul Breaks-00001", dbID: "SB-1", imageURL: nil,
             values: [(title: "Name", value: "Omnislash"), (title: "Effects", value: "azimuth")])
        ])
        try await index.indexSheet(title: "Other", rows: [
            (id: "Other-00001", dbID: "Other-1", imageURL: nil,
             values: [(title: "Name", value: "Compass"),
                      (title: "Description", value: "azimuth azimuth azimuth azimuth azimuth")])
        ])
        try await index.commitRebuild()

        let results = try await index.search(query: "azimuth")
        XCTAssertEqual(results.sections.map(\.sheetTitle), ["Characters", "Soul Breaks"])
        XCTAssertEqual(results.rest.map(\.sheetTitle), ["Other"])
    }

    func testFTS5PerSectionLimit() async throws {
        let queue = try makeQueue()
        let index = SearchIndex(db: queue)

        // Pack one sheet with 8 matching rows; cap each section at 3.
        let manyRows = (1...8).map { i in
            (
                id: "Soul Breaks-\(String(format: "%05d", i))",
                dbID: "SB-\(i)",
                imageURL: nil as String?,
                values: [
                    (title: "Name", value: "Burst \(i)"),
                    (title: "Effects", value: "azimuth swing")
                ]
            )
        }
        try await index.beginRebuild()
        try await index.indexSheet(title: "Soul Breaks", rows: manyRows)
        try await index.indexSheet(title: "Characters", rows: [
            (id: "Characters-00001", dbID: "Characters-1", imageURL: nil,
             values: [(title: "Name", value: "Cloud"), (title: "Notes", value: "azimuth")])
        ])
        try await index.commitRebuild()

        let results = try await index.search(query: "azimuth", perSectionLimit: 3)
        XCTAssertEqual(results.sections.map(\.sheetTitle), ["Characters", "Soul Breaks"])
        XCTAssertEqual(results.sections[0].results.count, 1)
        XCTAssertEqual(results.sections[1].results.count, 3)
        XCTAssertTrue(results.rest.isEmpty)
    }

    func testFTS5MultiTokenAndAnyOrder() async throws {
        let queue = try makeQueue()
        let index = SearchIndex(db: queue)

        // Three Soul Breaks: one matches both tokens, the other two match only one each.
        try await index.beginRebuild()
        try await index.indexSheet(title: "Soul Breaks", rows: [
            (id: "Soul Breaks-00001", dbID: "SB-1", imageURL: nil,
             values: [(title: "Name", value: "Cloud DASB"),
                      (title: "Character", value: "Cloud"),
                      (title: "Tier", value: "DASB")]),
            (id: "Soul Breaks-00002", dbID: "SB-2", imageURL: nil,
             values: [(title: "Name", value: "Cloud OSB"),
                      (title: "Character", value: "Cloud"),
                      (title: "Tier", value: "OSB")]),
            (id: "Soul Breaks-00003", dbID: "SB-3", imageURL: nil,
             values: [(title: "Name", value: "Tifa DASB"),
                      (title: "Character", value: "Tifa"),
                      (title: "Tier", value: "DASB")])
        ])
        try await index.commitRebuild()

        let forward = try await index.search(query: "cloud dasb")
        let reverse = try await index.search(query: "dasb cloud")

        XCTAssertEqual(forward.sections.flatMap(\.results).map(\.id), ["Soul Breaks-00001"])
        XCTAssertEqual(reverse.sections.flatMap(\.results).map(\.id), ["Soul Breaks-00001"])
    }

    func testTierPrefixDetection() {
        XCTAssertNil(SearchIndex.sheets(matchingPrefixIn: ""))
        XCTAssertNil(SearchIndex.sheets(matchingPrefixIn: "   "))
        XCTAssertNil(SearchIndex.sheets(matchingPrefixIn: "cloud"))
        XCTAssertNil(SearchIndex.sheets(matchingPrefixIn: "cloud dasb"))
        XCTAssertEqual(SearchIndex.sheets(matchingPrefixIn: "dasb"), ["Soul Breaks"])
        XCTAssertEqual(SearchIndex.sheets(matchingPrefixIn: "dasb cloud"), ["Soul Breaks"])
        XCTAssertEqual(SearchIndex.sheets(matchingPrefixIn: "DASB cloud"), ["Soul Breaks"])
        XCTAssertEqual(SearchIndex.sheets(matchingPrefixIn: "Dasb cloud"), ["Soul Breaks"])
        XCTAssertEqual(SearchIndex.sheets(matchingPrefixIn: "ha cloud"), ["Hero Abilities"])
    }

    func testTierAliasCanonicalization() {
        // Aliased tier: zsb / uasb / z / ua all resolve to canonical "zsb".
        XCTAssertEqual(SearchIndex.canonicalize("zsb cloud"), "zsb cloud")
        XCTAssertEqual(SearchIndex.canonicalize("uasb cloud"), "zsb cloud")
        XCTAssertEqual(SearchIndex.canonicalize("z cloud"), "zsb cloud")
        XCTAssertEqual(SearchIndex.canonicalize("ua cloud"), "zsb cloud")
        XCTAssertEqual(SearchIndex.canonicalize("Z cloud"), "zsb cloud")
        XCTAssertEqual(SearchIndex.canonicalize("UA cloud"), "zsb cloud")

        // No rewrite when first token already is the canonical.
        XCTAssertEqual(SearchIndex.canonicalize("dasb cloud"), "dasb cloud")

        // Only first token is checked; aliases mid-query are left alone.
        XCTAssertEqual(SearchIndex.canonicalize("cloud z"), "cloud z")

        // Unknown first token: no change.
        XCTAssertEqual(SearchIndex.canonicalize("foo cloud"), "foo cloud")

        // Empty / whitespace-only.
        XCTAssertEqual(SearchIndex.canonicalize(""), "")
        XCTAssertEqual(SearchIndex.canonicalize("   "), "   ")
    }

    func testFTS5AliasResolvesToCanonical() async throws {
        let queue = try makeQueue()
        let index = SearchIndex(db: queue)

        try await index.beginRebuild()
        try await index.indexSheet(title: "Soul Breaks", rows: [
            (id: "Soul Breaks-00001", dbID: "SB-1", imageURL: nil,
             values: [(title: "Name", value: "Cloud ZSB"),
                      (title: "Character", value: "Cloud"),
                      (title: "Tier", value: "ZSB")])
        ])
        // Decoy: Zell row with Cloud not appearing — without canonicalization, the
        // short alias "z cloud" via prefix wildcard could match "Zell" tokens.
        try await index.indexSheet(title: "Characters", rows: [
            (id: "Characters-00001", dbID: "Characters-1", imageURL: nil,
             values: [(title: "Name", value: "Zell"), (title: "Realm", value: "VIII")])
        ])
        try await index.commitRebuild()

        let viaShortAlias = try await index.search(query: "z cloud", sheets: ["Soul Breaks"])
        let viaCanonical = try await index.search(query: "zsb cloud", sheets: ["Soul Breaks"])
        let viaOtherAlias = try await index.search(query: "ua cloud", sheets: ["Soul Breaks"])
        let viaOtherCanonical = try await index.search(query: "uasb cloud", sheets: ["Soul Breaks"])

        let expected = ["Soul Breaks-00001"]
        XCTAssertEqual((viaShortAlias.sections.flatMap(\.results) + viaShortAlias.rest).map(\.id), expected)
        XCTAssertEqual((viaCanonical.sections.flatMap(\.results) + viaCanonical.rest).map(\.id), expected)
        XCTAssertEqual((viaOtherAlias.sections.flatMap(\.results) + viaOtherAlias.rest).map(\.id), expected)
        XCTAssertEqual((viaOtherCanonical.sections.flatMap(\.results) + viaOtherCanonical.rest).map(\.id), expected)
    }

    func testFTS5DasbCloudFindsSoulBreak() async throws {
        let queue = try makeQueue()
        let index = SearchIndex(db: queue)

        try await index.beginRebuild()
        try await index.indexSheet(title: "Characters", rows: [
            (id: "Characters-00001", dbID: "Characters-1", imageURL: nil,
             values: [(title: "Name", value: "Cloud"), (title: "Realm", value: "VII")])
        ])
        try await index.indexSheet(title: "Soul Breaks", rows: [
            (id: "Soul Breaks-00001", dbID: "SB-1", imageURL: nil,
             values: [(title: "Name", value: "Cloud DASB"),
                      (title: "Character", value: "Cloud"),
                      (title: "Tier", value: "DASB")]),
            (id: "Soul Breaks-00002", dbID: "SB-2", imageURL: nil,
             values: [(title: "Name", value: "Cloud OSB"),
                      (title: "Character", value: "Cloud"),
                      (title: "Tier", value: "OSB")])
        ])
        try await index.commitRebuild()

        let sheets = try XCTUnwrap(SearchIndex.sheets(matchingPrefixIn: "dasb cloud"))
        let results = try await index.search(query: "dasb cloud", sheets: sheets)

        // Restricted to Soul Breaks; the Cloud Characters row should not appear, nor Cloud OSB.
        let allResults = results.sections.flatMap(\.results) + results.rest
        XCTAssertEqual(allResults.map(\.id), ["Soul Breaks-00001"])
    }

    func testFTS5BuildFTSQuery() {
        // Direct unit test of the query builder so future regressions are obvious.
        XCTAssertNil(SearchIndex.buildFTSQuery(from: ""))
        XCTAssertNil(SearchIndex.buildFTSQuery(from: "   "))
        XCTAssertEqual(SearchIndex.buildFTSQuery(from: "cloud"), "\"cloud\"*")
        XCTAssertEqual(SearchIndex.buildFTSQuery(from: "cloud dasb"), "\"cloud\"* \"dasb\"*")
        XCTAssertEqual(SearchIndex.buildFTSQuery(from: "  cloud   dasb  "), "\"cloud\"* \"dasb\"*")
        XCTAssertEqual(SearchIndex.buildFTSQuery(from: "cloud\"strife"), "\"cloud\"\"strife\"*")
    }

    func testFTS5RestLimit() async throws {
        let queue = try makeQueue()
        let index = SearchIndex(db: queue)

        // Pack a non-priority sheet with 25 matching rows; ask for restLimit: 7.
        let manyRows = (1...25).map { i in
            (
                id: "Other-\(String(format: "%05d", i))",
                dbID: "Other-\(i)",
                imageURL: nil as String?,
                values: [
                    (title: "Name", value: "Item \(i)"),
                    (title: "Description", value: "azimuth")
                ]
            )
        }
        try await index.beginRebuild()
        try await index.indexSheet(title: "Other", rows: manyRows)
        try await index.commitRebuild()

        let results = try await index.search(query: "azimuth", restLimit: 7)
        XCTAssertTrue(results.sections.isEmpty)
        XCTAssertEqual(results.rest.count, 7)
    }
}
