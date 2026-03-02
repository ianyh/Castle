//
//  SpreadsheetsClient.swift
//  Castle
//
//  Created by Ian Ynda-Hummel on 9/1/18.
//  Copyright © 2018 Ian Ynda-Hummel. All rights reserved.
//

import Alamofire
import CouchbaseLiteSwift
import Foundation
import Kingfisher
import RealmSwift

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
    private static let spreadsheetID = "1f8OJIQhpycljDQ8QNDk_va1GJ1u7RVoMaNjFcHH0LKk"
    private static let ignoredSheets = ["Header", "Calculator", "Experience", "Events", "Missions", "Crystal Reqs"]

    init() {
        session.configuration.timeoutIntervalForRequest = 120
        session.configuration.timeoutIntervalForResource = 120
    }

    @MainActor
    func sync() async throws {
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

        let spreadsheet = try JSONDecoder().decode(Spreadsheet.self, from: responseData)
        let sheets = spreadsheet.sheets.filter {
            $0.properties.gridProperties.columnCount > 1
                && !SpreadsheetsClient.ignoredSheets.contains($0.properties.title)
                && !$0.properties.title.lowercased().contains("(old)")
        }

        let encoder = URLEncodedFormParameterEncoder(encoder: URLEncodedFormEncoder(arrayEncoding: .noBrackets))
        let valuesURLComponents = URLComponents(
            string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetID)/values:batchGet"
        )!
        let baseRequest = try! encoder.encode(
            ["ranges": sheets.map { $0.properties.title }],
            into: URLRequest(url: valuesURLComponents.url!)
        )
        let valuesRequest = try! encoder.encode(["valueRenderOption": "FORMATTED_VALUE", "key": key], into: baseRequest)
        let rawValuesRequest = try! encoder.encode(["valueRenderOption": "FORMULA", "key": key], into: baseRequest)

        async let valuesResult = session.data(for: valuesRequest)
        async let rawValuesResult = session.data(for: rawValuesRequest)
        let ((valuesData, _), (rawValuesData, _)) = try await (valuesResult, rawValuesResult)

        let ranges = try JSONDecoder().decode(SpreadsheetValues.self, from: valuesData).ranges
        let rawRanges = try JSONDecoder().decode(SpreadsheetRawValues.self, from: rawValuesData).ranges

        let spreadsheets = try zip(ranges, rawRanges).compactMap { range, rawRange -> SpreadsheetObject? in
            guard let sheet = sheets.first(where: {
                range.range.hasPrefix($0.properties.title) || range.range.hasPrefix("'\($0.properties.title)'")
            }) else {
                return nil
            }
            return try object(for: sheet, values: range, rawValues: rawRange)
        }

        let realm = try await Realm()
        try realm.write {
            realm.add(spreadsheets, update: .modified)
        }
        try LastUpdateObject.markUpdate()

        var ftsIndices = Set(["Effects", "Element", "Tier"])
        do {
            try Database(name: "search").delete()
        } catch {
            print("failed to delete")
        }

        let database = try Database(name: "search")
        do {
            try database.inBatch {
                for sheet in spreadsheets {
                    for row in sheet.rows {
                        let document = try database.defaultCollection().document(id: row.id)?.toMutable() ?? MutableDocument(id: row.id)
                        document.setString(row.values.first { $0.imageURL != nil }?.imageURL, forKey: "_imageURL")
                        document.setString(sheet.title, forKey: "_sheetTitle")
                        for value in row.values where !value.value.isEmpty && !value.title.isEmpty {
                            document.setString(value.value, forKey: value.title)
                        }
                        try database.defaultCollection().save(document: document)
                    }

                    let frozenColumns = sheet.columns.filter({ $0.isColumnFrozen && !$0.title.isEmpty }).map { $0.title }
                    ftsIndices.formUnion(frozenColumns)

                    if let nameJPColumn = sheet.columns.first(where: { $0.title == "Name (JP)" }) {
                        ftsIndices.insert(nameJPColumn.title)
                    }
                }
            }
        } catch {
            print(error)
            throw error
        }

        let index = IndexBuilder.fullTextIndex(items: ftsIndices.map { FullTextIndexItem.property($0) })
        do {
            try database.defaultCollection().createIndex(index, name: "searchIndex")
        } catch {
            print(error)
            throw error
        }
    }

    @MainActor
    func preloadImages() -> AsyncThrowingStream<String, Swift.Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let realm = try await Realm()
                    let urls = Array(
                        realm.objects(RowValueObject.self).filter("imageURL != nil")
                            .compactMap { $0.imageURL }
                            .sorted()
                            .compactMap { URL(string: $0)?.cleaned() }
                    )
                    let urlCount = urls.count
                    let urlChunks = urls.chunked(into: urlCount / 10)
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
                    if columnIndex < rawRow.count, case .some(let columnValue) = rawRow[columnIndex] {
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
                        if columnIndex < rawRow.count, case let .some(columnValue) = rawRow[columnIndex] {
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

    func object(for sheet: Sheet, values: SpreadsheetRange, rawValues: SpreadsheetRawRange) throws -> SpreadsheetObject {
        let headers = values.rows[0]
        let frozenColumnCount = sheet.properties.gridProperties.frozenColumnCount ?? 0
        let columns = headers.enumerated().compactMap { index, value -> ColumnObject? in
            guard value != "Img" else {
                return nil
            }

            let column = ColumnObject()
            column.key = "\(sheet.properties.id)-\(value)"
            column.isColumnFrozen = index < frozenColumnCount || forceFrozenColumns.contains(value)
            column.title = value
            return column
        }
        let nameColumn = columns.first { $0.title.hasSuffix("Name") }
        let idColumn = columns.first { $0.title == "ID" }
        let otherColumns = columns.filter { $0 != nameColumn }
        let sortedColumns = nameColumn.flatMap { [$0] + otherColumns } ?? otherColumns

        let rows = zip(values.rows[1...], rawValues.rows[1...]).map { (row, rawRow) -> RowObject in
            let rowObject = RowObject()
            let rowValues = zip(row, rawRow).prefix(headers.count).enumerated().map { (index, value) -> RowValueObject in
                let normalized = value.1
                let imageURL: String? = self.extractImageURL(from: normalized, rawRow: rawRow)

                let rowValue = RowValueObject()
                rowValue.column = columns.first { $0.title == headers[index] }
                rowValue.title = headers[index]
                rowValue.value = value.0
                rowValue.imageURL = imageURL

                if rowValue.column == idColumn {
                    rowObject.dbID = "\(sheet.properties.title)-\(value.0)"
                }

                return rowValue
            }

            rowObject.values.append(objectsIn: rowValues)

            return rowObject
        }

        rows.enumerated().forEach { index, row in
            row.id = "\(sheet.properties.title)-\(String(format: "%05d", index))"
            row.values.enumerated().forEach { valueIndex, value in
                value.id = "\(row.id)-\(String(format: "%05d", valueIndex))"
            }
        }

        let sheetObject = SpreadsheetObject()
        sheetObject.title = sheet.properties.title
        sheetObject.columns.append(objectsIn: sortedColumns)
        sheetObject.rows.append(objectsIn: rows)

        return sheetObject
    }

    private func columnToIndex(_ column: String) -> Int {
        var result = 0
        for columnChar in column {
            result *= 26
            result += Int(columnChar.asciiValue! - Character("a").asciiValue!) + 1
        }
        return result - 1
    }
}
