//
//  SpreadsheetsClient.swift
//  Castle
//
//  Created by Ian Ynda-Hummel on 9/1/18.
//  Copyright © 2018 Ian Ynda-Hummel. All rights reserved.
//

import Foundation
import GRDB
import Kingfisher

let pattern = ".*=image\\(\"(.+?)\".*\\).*"
let embeddedPattern = "\"([a-zA-Z0-9-._~:/?#@!$&'()*+,;=]*)\"|&\\s*([a-zA-Z0-9_]+)"
let concatPattern = ".*=image\\(concatenate\\((.*?)\\).*?\\).*"
let regex = try! NSRegularExpression(pattern: pattern, options: [])
let embeddedRegex = try! NSRegularExpression(pattern: embeddedPattern, options: [])
let concatRegex = try! NSRegularExpression(pattern: concatPattern, options: [])

private let forceFrozenColumns = Set([
    "Effects"
])

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}

private actor ImageCounter {
    private(set) var count = 0
    func increment() -> Int {
        count += 1
        return count
    }
}

class SpreadsheetsClient {
    enum Error: Swift.Error {
        case failedSync
    }

    private let session = URLSession(configuration: URLSession.shared.configuration)
    private let db: DatabaseQueue
    private static let spreadsheetID = "1f8OJIQhpycljDQ8QNDk_va1GJ1u7RVoMaNjFcHH0LKk"
    private static let ignoredSheets = [
        "Header",
        "Calculator",
        "Experience",
        "Events",
        "Missions",
        "Crystal Reqs",
        "Artifacts",
        "Record Boards",
        "Record Spheres",
        "Relics",
        "SB/LB Honing Effect Details"
    ]

    init(db: DatabaseQueue) {
        self.db = db
        session.configuration.timeoutIntervalForRequest = 120
        session.configuration.timeoutIntervalForResource = 120
    }

    func sync(searchIndex: SearchIndex) async throws {
        guard
            let infoPath = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
            let info = NSDictionary(contentsOf: URL(fileURLWithPath: infoPath)),
            let key = info["API_KEY"] as? String
        else {
            return
        }

        let spreadsheetID = SpreadsheetsClient.spreadsheetID
        var urlComponents = URLComponents(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetID)")!
        urlComponents.queryItems = [
            URLQueryItem(name: "key", value: key),
            URLQueryItem(name: "fields", value: "sheets.properties")
        ]

        let (responseData, _) = try await session.data(for: URLRequest(url: urlComponents.url!))

        let spreadsheet = try JSONDecoder().decode(SpreadsheetAPIResponse.self, from: responseData)
        let sheets = spreadsheet.sheets.filter {
            $0.properties.gridProperties.columnCount > 1
                && !SpreadsheetsClient.ignoredSheets.contains($0.properties.title)
                && !$0.properties.title.lowercased().contains("(old)")
        }

        var valuesComponents = URLComponents(
            string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetID)/values:batchGet"
        )!
        let rangeItems = sheets.map { URLQueryItem(name: "ranges", value: $0.properties.title) }
        let commonItems = rangeItems + [URLQueryItem(name: "key", value: key)]

        valuesComponents.queryItems = commonItems + [URLQueryItem(name: "valueRenderOption", value: "FORMATTED_VALUE")]
        let valuesRequest = URLRequest(url: valuesComponents.url!)

        valuesComponents.queryItems = commonItems + [URLQueryItem(name: "valueRenderOption", value: "FORMULA")]
        let rawValuesRequest = URLRequest(url: valuesComponents.url!)

        async let valuesResult = session.data(for: valuesRequest)
        async let rawValuesResult = session.data(for: rawValuesRequest)
        let ((valuesData, _), (rawValuesData, _)) = try await (valuesResult, rawValuesResult)

        let ranges = try JSONDecoder().decode(SpreadsheetValues.self, from: valuesData).ranges
        let rawRanges = try JSONDecoder().decode(SpreadsheetRawValues.self, from: rawValuesData).ranges

        // Clear existing data before inserting fresh.
        try await db.write { db in
            try db.execute(sql: "DELETE FROM spreadsheets")
            try db.execute(sql: "DELETE FROM spreadsheet_rows")
            try db.execute(sql: "DELETE FROM last_update")
        }

        // Begin the search index transaction that will span all sheets.
        try await searchIndex.beginRebuild()

        // Process one sheet at a time. Each sheet is written in its own DB transaction
        // so memory for that sheet's rows can be released before the next sheet is built.
        for (range, rawRange) in zip(ranges, rawRanges) {
            guard let sheet = sheets.first(where: {
                range.range.hasPrefix($0.properties.title) || range.range.hasPrefix("'\($0.properties.title)'")
            }) else {
                continue
            }

            let (spreadsheet, rows) = try object(for: sheet, values: range, rawValues: rawRange)

            let indexRows = rows.map { row in
                (
                    id: row.id,
                    dbID: row.dbID,
                    imageURL: row.values.first(where: { $0.imageURL != nil })?.imageURL,
                    values: row.values.map { (title: $0.title, value: $0.value) }
                )
            }
            try await searchIndex.indexSheet(title: spreadsheet.title, rows: indexRows)

            try await db.write { db in
                try spreadsheet.insert(db, onConflict: .replace)
                for row in rows {
                    try row.insert(db, onConflict: .replace)
                }
            }
        }

        try await searchIndex.commitRebuild()

        try await db.write { db in
            try LastUpdate(date: Date()).insert(db, onConflict: .replace)
        }
    }

    func preloadImages() -> AsyncThrowingStream<String, Swift.Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let rows = try await self.db.read { try SpreadsheetRow.fetchAll($0) }
                    let urls = rows
                        .flatMap { $0.values }
                        .compactMap { $0.imageURL }
                        .sorted()
                        .compactMap { URL(string: $0)?.cleaned() }

                    let urlCount = urls.count
                    guard urlCount > 0 else {
                        continuation.finish()
                        return
                    }
                    let urlChunks = urls.chunked(into: max(1, urlCount / 10))
                    continuation.yield("0/\(urlCount)")

                    let counter = ImageCounter()
                    await withTaskGroup(of: Void.self) { group in
                        for chunk in urlChunks {
                            group.addTask {
                                for url in chunk {
                                    await self.preloadImage(with: url)
                                    let count = await counter.increment()
                                    continuation.yield("\(count)/\(urlCount)")
                                }
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func preloadImage(with url: URL) async {
        guard KingfisherManager.shared.cache.imageCachedType(forKey: url.cleaned().cacheKey) != .disk else {
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            KingfisherManager.shared.retrieveImage(with: url, options: nil, progressBlock: nil) { _ in
                continuation.resume()
            }
        }
    }

    func clearImageCache() {
        KingfisherManager.shared.cache.clearDiskCache()
    }

    func extractImageURL(from value: RawValue, rawRow: [RawValue]) -> String? {
        var imageURL: String? = nil

        guard case .some(let normalized) = value, normalized.lowercased().hasPrefix("=image") else {
            return nil
        }

        let lowerNormalized = normalized.lowercased()
        let range = NSRange(lowerNormalized.startIndex..<lowerNormalized.endIndex, in: lowerNormalized)
        let embeddedMatches = embeddedRegex.matches(in: lowerNormalized, options: [], range: range)
        let concatMatches = concatRegex.matches(in: lowerNormalized, options: [], range: range)
        let matches = regex.matches(in: lowerNormalized, options: [], range: range)

        if
            let match = concatMatches.first, match.numberOfRanges == 2,
            let argumentsString = Range(match.range(at: 1), in: lowerNormalized).flatMap({ String(lowerNormalized[$0]) })
        {
            let arguments = argumentsString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            imageURL = arguments.reduce("") { string, arg -> String in
                if arg.isEmpty {
                    return string
                } else if arg.hasPrefix("\"") && arg.hasSuffix("\"") {
                    let startIndex = arg.index(after: arg.startIndex)
                    let lastIndex = arg.index(before: arg.endIndex)
                    return string + arg[startIndex..<lastIndex]
                } else {
                    let alphabetic = arg.trimmingCharacters(in: .decimalDigits)
                    let columnIndex = self.columnToIndex(alphabetic)
                    if columnIndex >= 0, columnIndex < rawRow.count, case .some(let columnValue) = rawRow[columnIndex] {
                        return string + columnValue
                    }
                    return string
                }
            }
        } else if !embeddedMatches.isEmpty {
            var strings: [String] = []
            for match in embeddedMatches {
                if let range = Range(match.range, in: lowerNormalized) {
                    let substring = lowerNormalized[range]
                    if substring.contains("\"") {
                        strings.append(String(substring.dropFirst().dropLast()))
                    } else {
                        let column = substring.replacingOccurrences(of: "&", with: "").trimmingCharacters(in: .whitespaces)
                        let alphabetic = column.trimmingCharacters(in: .decimalDigits)
                        let columnIndex = self.columnToIndex(alphabetic)
                        if columnIndex >= 0, columnIndex < rawRow.count, case let .some(columnValue) = rawRow[columnIndex] {
                            strings.append(columnValue)
                        }
                    }
                }
            }
            imageURL = strings.joined(separator: "")
        } else if let match = matches.first, match.numberOfRanges == 2 {
            let range = match.range(at: 1)
            imageURL = Range(range, in: lowerNormalized).flatMap { String(normalized[$0]) }
        }
        return imageURL
    }

    func object(for sheet: Sheet, values: SpreadsheetRange, rawValues: SpreadsheetRawRange) throws -> (Spreadsheet, [SpreadsheetRow]) {
        let headers = values.rows[0]
        let frozenColumnCount = sheet.properties.gridProperties.frozenColumnCount ?? 0
        let columns = headers.enumerated().compactMap { index, value -> SpreadsheetColumn? in
            guard value != "Img" else { return nil }
            return SpreadsheetColumn(
                key: "\(sheet.properties.id)-\(value)",
                isColumnFrozen: index < frozenColumnCount || forceFrozenColumns.contains(value),
                title: value
            )
        }
        let nameColumn = columns.first { $0.title.hasSuffix("Name") }
        let idColumn = columns.first { $0.title == "ID" }
        let otherColumns = columns.filter { $0.key != nameColumn?.key }
        let sortedColumns = nameColumn.flatMap { [$0] + otherColumns } ?? otherColumns

        let rows = zip(values.rows[1...], rawValues.rows[1...]).enumerated().map { (rowIndex, pair) -> SpreadsheetRow in
            let (row, rawRow) = pair
            let rowID = "\(sheet.properties.title)-\(String(format: "%05d", rowIndex))"

            let rowValues: [RowValue] = zip(row, rawRow).prefix(headers.count).enumerated().map { (index, valuePair) in
                let (formattedValue, rawValue) = valuePair
                let imageURL = self.extractImageURL(from: rawValue, rawRow: Array(rawRow))
                let matchingColumn = columns.first { $0.title == headers[index] }
                let isFrozen = imageURL != nil || (matchingColumn?.isColumnFrozen ?? false)
                return RowValue(
                    id: "\(rowID)-\(String(format: "%05d", index))",
                    columnKey: matchingColumn?.key,
                    columnTitle: headers[index],
                    isColumnFrozen: isFrozen,
                    title: headers[index],
                    value: formattedValue,
                    imageURL: imageURL
                )
            }

            let dbID: String
            if let idColKey = idColumn?.key,
               let idValue = rowValues.first(where: { $0.columnKey == idColKey }) {
                dbID = "\(sheet.properties.title)-\(idValue.value)"
            } else {
                dbID = ""
            }

            return SpreadsheetRow(id: rowID, dbID: dbID, spreadsheetTitle: sheet.properties.title, values: rowValues)
        }

        let spreadsheetObj = Spreadsheet(title: sheet.properties.title, columns: sortedColumns)
        return (spreadsheetObj, rows)
    }

    // Returns 0-based column index from a spreadsheet column letter ("a"→0, "b"→1, "aa"→26).
    // Returns -1 for empty input or any non-lowercase-letter character (bare numbers, $, etc.).
    private func columnToIndex(_ column: String) -> Int {
        guard !column.isEmpty else { return -1 }
        let aValue = Int(Character("a").asciiValue!)
        var result = 0
        for columnChar in column {
            guard let ascii = columnChar.asciiValue, ascii >= 97, ascii <= 122 else { return -1 }
            result = result * 26 + (Int(ascii) - aValue + 1)
        }
        return result - 1
    }
}
