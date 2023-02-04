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
import RxCocoa
import RxSwift

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}

class SpreadsheetsClient {
    enum Error: Swift.Error {
        case failedSync
    }
    
    private let reloadQueue = DispatchQueue(label: "com.ianyh.Castle.reload")
    private let session = URLSession(configuration: URLSession.shared.configuration)
    private static let spreadsheetID = "1f8OJIQhpycljDQ8QNDk_va1GJ1u7RVoMaNjFcHH0LKk"
    private static let ignoredSheets = ["Header", "Calculator", "Experience", "Events", "Missions", "Crystal Reqs"]
    
    init() {
        session.configuration.timeoutIntervalForRequest = 120
        session.configuration.timeoutIntervalForResource = 120
    }
    
    func sync() -> Observable<Void> {
        guard
            let infoPath = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
            let info = NSDictionary(contentsOf: URL(fileURLWithPath: infoPath)),
            let key = info["API_KEY"] as? String
        else {
            return .just(())
        }
        
        let spreadsheetID = SpreadsheetsClient.spreadsheetID
        let scheduler = SerialDispatchQueueScheduler(queue: reloadQueue, internalSerialQueueName: reloadQueue.label)
        var urlComponents = URLComponents(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetID)")!
        urlComponents.queryItems = [
            URLQueryItem(name: "key", value: key),
            URLQueryItem(name: "fields", value: "sheets.properties")
        ]
        let request = URLRequest(url: urlComponents.url!)

        return session.rx.data(request: request)
            .observe(on: scheduler)
            .flatMap { [weak self] response -> Observable<Void> in
                guard let `self` = self else {
                    return .just(())
                }
                
                let spreadsheet = try JSONDecoder().decode(Spreadsheet.self, from: response)
                let sheets = spreadsheet.sheets.filter {
                    $0.properties.gridProperties.columnCount > 1
                        && !SpreadsheetsClient.ignoredSheets.contains($0.properties.title)
                        && !$0.properties.title.lowercased().contains("(old)")
                }
                let encoder = URLEncodedFormParameterEncoder(encoder: URLEncodedFormEncoder(arrayEncoding: .noBrackets))
                let urlComponents = URLComponents(
                    string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetID)/values:batchGet"
                )!
                let request = try! encoder.encode(["ranges": sheets.map { $0.properties.title }], into: URLRequest(url: urlComponents.url!))

                let valuesParameters = [
                    "valueRenderOption": "FORMATTED_VALUE",
                    "key": key
                ]
                let valuesRequest = try! encoder.encode(valuesParameters, into: request)
                
                let rawValuesParameters = [
                    "valueRenderOption": "FORMULA",
                    "key": key
                ]
                let rawValuesRequest = try! encoder.encode(rawValuesParameters, into: request)

                let valuesRequests = Observable.zip([
                    self.session.rx.data(request: valuesRequest),
                    self.session.rx.data(request: rawValuesRequest)
                ]) { ($0[0], $0[1]) }

                return valuesRequests
                    .map { [weak self] responses -> [SpreadsheetObject] in
                        guard let `self` = self else {
                            throw Error.failedSync
                        }
                        
                        let ranges = try JSONDecoder().decode(SpreadsheetValues.self, from: responses.0).ranges
                        let rawRanges = try JSONDecoder().decode(SpreadsheetRawValues.self, from: responses.1).ranges

                        return try zip(ranges, rawRanges).compactMap { range, rawRange -> SpreadsheetObject? in
                            guard let sheet = sheets.first(where: { range.range.hasPrefix($0.properties.title) || range.range.hasPrefix("'\($0.properties.title)'") }) else {
                                return nil
                            }
                            return try self.object(for: sheet, values: range, rawValues: rawRange)
                        }
                    }
                    .do(
                        onNext: { spreadsheets in
                            let realm = try Realm()
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
                                            let document = database.document(withID: row.id)?.toMutable() ?? MutableDocument(id: row.id)
                                            document.setString(row.values.first { $0.imageURL != nil }?.imageURL, forKey: "_imageURL")
                                            document.setString(sheet.title, forKey: "_sheetTitle")
                                            for value in row.values where !value.value.isEmpty && !value.title.isEmpty {
                                                document.setString(value.value, forKey: value.title)
                                            }
                                            try database.saveDocument(document)
                                        }
                                        
                                        for column in sheet.columns.filter({ $0.isColumnFrozen == true }) where !column.title.isEmpty {
                                            ftsIndices.insert(column.title)
                                        }
                                    }
                                }
                            } catch {
                                print(error)
                                throw error
                            }

                            let index = IndexBuilder.fullTextIndex(items: ftsIndices.map { FullTextIndexItem.property($0) })
                            do {
                                try database.createIndex(index, withName: "searchIndex")
                            } catch {
                                print(error)
                                throw error
                            }
                        }
                    )
                    .map { _ in }
            }
    }
    
    func preloadImages() -> Observable<String> {
        do {
            let realm = try Realm()
            let urls = Array(
                realm.objects(RowValueObject.self).filter("imageURL != nil")
                    .compactMap { $0.imageURL }
                    .sorted()
                    .compactMap { URL(string: $0)?.cleaned() }
            )
            let urlCount = urls.count
            let urlChunks = urls.chunked(into: urlCount / 10)
            let downloads = Observable.merge(urlChunks.map { chunk in
                return Observable.concat(chunk.map { self.preloadImage(with: $0) })
            })
            
            return downloads
                .scan(0) { count, _ -> Int in count + 1 }
                .map { "\($0)/\(urlCount)" }
                .startWith("0/\(urlCount)")
        } catch {
            return .error(error)
        }
    }
    
    func preloadImage(with url: URL) -> Observable<Void> {
        return Observable<Void>.create { observer in
            guard KingfisherManager.shared.cache.imageCachedType(forKey: url.cleaned().cacheKey) != .disk else {
                DispatchQueue.main.async {
                    observer.on(.next(()))
                    observer.on(.completed)
                }
                return Disposables.create()
            }
            
            let task = KingfisherManager.shared.retrieveImage(with: url, options: nil, progressBlock: nil) { _ in
                DispatchQueue.main.async {
                    observer.on(.next(()))
                    observer.on(.completed)
                }
            }
            
            return Disposables.create {
                task?.cancel()
            }
        }
    }
    
    func clearImageCache() {
        KingfisherManager.shared.cache.clearDiskCache()
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
            column.isColumnFrozen = index < frozenColumnCount
            column.title = value
            return column
        }
        let nameColumn = columns.first { $0.title.hasSuffix("Name") }
        let otherColumns = columns.filter { $0 != nameColumn }
        let sortedColumns = nameColumn.flatMap { [$0] + otherColumns } ?? otherColumns
        
        let pattern = ".*=image\\(\"(.+?)\".*\\).*"
        let embeddedPattern = ".*=image\\(\"(.+?)\".*?&.*?(\\w+).*?&.*?\"(.+?)\"\\).*"
        let regex = try! NSRegularExpression(pattern: pattern, options: [])
        let embeddedRegex = try! NSRegularExpression(pattern: embeddedPattern, options: [])

        let rows = zip(values.rows[1...], rawValues.rows[1...]).map { (row, rawRow) -> RowObject in
            let rowObject = RowObject()
            let rowValues = zip(row, rawRow).prefix(headers.count).enumerated().map { (index, value) -> RowValueObject in
                let normalized = value.1
                var imageURL: String? = nil

                if case let .some(normalized) = normalized, normalized.lowercased().hasPrefix("=image") {
                    let lowerNormalized = normalized.lowercased()
                    let range = NSRange(lowerNormalized.startIndex..<lowerNormalized.endIndex, in: lowerNormalized)
                    let embeddedMatches = embeddedRegex.matches(in: lowerNormalized, options: [], range: range)
                    let matches = regex.matches(in: lowerNormalized, options: [], range: range)
                    
                    if
                        let match = embeddedMatches.first, match.numberOfRanges == 4,
                        let prefix = Range(match.range(at: 1), in: lowerNormalized).flatMap({ String(lowerNormalized[$0]) }),
                        let column = Range(match.range(at: 2), in: lowerNormalized).flatMap({ String(lowerNormalized[$0]) }),
                        let suffix = Range(match.range(at: 3), in: lowerNormalized).flatMap({ String(lowerNormalized[$0]) })
                    {
                        let columnIndex = Int(column.first!.asciiValue! - Character("a").asciiValue!)
                        if columnIndex < rawRow.count, case let .some(columnValue) = rawRow[columnIndex] {
                            imageURL = "\(prefix)\(columnValue)\(suffix)"
                        }
                    } else if let match = matches.first, match.numberOfRanges == 2 {
                        let range = match.range(at: 1)
                        imageURL = Range(range, in: lowerNormalized).flatMap { String(normalized[$0]) }
                    }
                }
                
                let rowValue = RowValueObject()
                rowValue.column = columns.first { $0.title == headers[index] }
                rowValue.title = headers[index]
                rowValue.value = value.0
                rowValue.imageURL = imageURL
                return rowValue
            }

            rowObject.values.append(objectsIn: rowValues)
            
            return rowObject
        }
        
        rows.enumerated().forEach { index, row in
            row.id = "\(sheet.properties.title)-\(index)"
            row.values.enumerated().forEach { valueIndex, value in
                value.id = "\(row.id)-\(valueIndex)"
            }
        }
        
        let sheetObject = SpreadsheetObject()
        sheetObject.title = sheet.properties.title
        sheetObject.columns.append(objectsIn: sortedColumns)
        sheetObject.rows.append(objectsIn: rows)
        
        return sheetObject
    }
}
