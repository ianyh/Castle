//
//  SpreadsheetsClient.swift
//  Castle
//
//  Created by Ian Ynda-Hummel on 9/1/18.
//  Copyright © 2018 Ian Ynda-Hummel. All rights reserved.
//

import Foundation
import Kingfisher
import Moya
import RealmSwift
import Result
import RxSwift

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}

class SpreadsheetsClient {
    private let reloadQueue = DispatchQueue(label: "com.ianyh.Castle.reload")
    private lazy var provider: MoyaProvider<Spreadsheets> = {
        return MoyaProvider<Spreadsheets>(callbackQueue: self.reloadQueue)
    }()
    private static let spreadsheetID = "1f8OJIQhpycljDQ8QNDk_va1GJ1u7RVoMaNjFcHH0LKk"
    private static let ignoredSheets = ["Header", "Calculator", "Experience"]
    
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
        
        return provider.rx.request(.spreadsheets(spreadsheetID: spreadsheetID, key: key))
            .asObservable()
            .observeOn(scheduler)
            .flatMap { [weak self] response -> Observable<Void> in
                guard let `self` = self else {
                    return .just(())
                }
                
                let spreadsheet = try JSONDecoder().decode(Spreadsheet.self, from: response.data)
                let loads = spreadsheet.sheets
                    .filter { $0.properties.gridProperties.columnCount > 1 }
                    .map { sheet -> Observable<SpreadsheetObject?> in
                        let valuesTarget: Spreadsheets = .values(spreadsheetID: spreadsheetID, sheet: sheet, key: key, raw: false)
                        let rawValuesTarget: Spreadsheets = .values(spreadsheetID: spreadsheetID, sheet: sheet, key: key, raw: true)
                        let valuesRequests = Observable.zip([
                            self.provider.rx.request(valuesTarget).asObservable().observeOn(scheduler),
                            self.provider.rx.request(rawValuesTarget).asObservable().observeOn(scheduler)
                        ]) { ($0[0], $0[1]) }
                        
                        return valuesRequests
                            .map { [weak self] responses -> SpreadsheetObject? in
                                guard let `self` = self else {
                                    return nil
                                }
                                
                                let object = try self.object(for: sheet, responses: responses)
                                
                                guard !SpreadsheetsClient.ignoredSheets.contains(object.title) else {
                                    return nil
                                }
                                
                                return object
                            }
                    }

                return Observable.zip(loads)
                    .map { $0.compactMap { $0 } }
                    .do(
                        onNext: { sheets in
                            let realm = try Realm()
                            try realm.write {
                                realm.add(sheets, update: true)
                            }
                            try LastUpdateObject.markUpdate()
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
                    .compactMap { imageURL -> URL? in
                        var components = URLComponents(string: imageURL)
                        components?.scheme = "https"
                        return components?.url
                    }
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
            guard KingfisherManager.shared.cache.imageCachedType(forKey: url.cacheKey) != .disk else {
                DispatchQueue.main.async {
                    observer.on(.next(()))
                    observer.on(.completed)
                }
                return Disposables.create()
            }
            
            let task = KingfisherManager.shared.retrieveImage(with: url, options: nil, progressBlock: nil) { _, _, _, _ in
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
    
    func object(for sheet: Sheet, responses: (Response, Response)) throws -> SpreadsheetObject {
        let response = responses.0
        let rawResponse = responses.1
        let values = try JSONDecoder().decode(SheetsValues.self, from: response.data)
        let rawValues = try JSONDecoder().decode(SheetsRawValues.self, from: rawResponse.data)
        let headers = values.rows[0]
        let frozenColumnCount = sheet.properties.gridProperties.frozenColumnCount ?? 0
        let columns = headers.enumerated().compactMap { index, value -> ColumnObject? in
            guard value != "Img" else {
                return nil
            }

            let column = ColumnObject()
            column.key = "\(sheet.properties.id)-\(value)"
            column.isFrozen = index < frozenColumnCount
            column.title = value
            return column
        }
        let nameColumn = columns.first { $0.title == "Name" }
        let otherColumns = columns.filter { $0 != nameColumn }
        let sortedColumns = nameColumn.flatMap { [$0] + otherColumns } ?? otherColumns
        
        let rows = zip(values.rows[1...], rawValues.rows[1...]).map { (row, rawRow) -> RowObject in
            let rowObject = RowObject()
            let rowValues = zip(row, rawRow).prefix(headers.count).enumerated().map { (index, value) -> RowValueObject in
                let normalized = value.1
                var imageURL: String? = nil
                
                if case let .some(normalized) = normalized {
                    let imageURLStartRange = normalized.lowercased().range(of: "=image(\"")
                    let imageURLEndRange = normalized.lowercased().range(of: "\")") ?? normalized.lowercased().range(of: "\";")

                    if let startRange = imageURLStartRange, let endRange = imageURLEndRange {
                        imageURL = String(normalized[startRange.upperBound..<endRange.lowerBound])
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
        let sheetObject = SpreadsheetObject()
        sheetObject.title = sheet.properties.title
        sheetObject.columns.append(objectsIn: sortedColumns)
        sheetObject.rows.append(objectsIn: rows)
        
        return sheetObject
    }
}
