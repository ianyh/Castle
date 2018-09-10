//
//  SpreadsheetsClient.swift
//  Castle
//
//  Created by Ian Ynda-Hummel on 9/1/18.
//  Copyright © 2018 Ian Ynda-Hummel. All rights reserved.
//

import Foundation
import Moya
import RealmSwift
import Result
import RxSwift

class SpreadsheetsClient {
    private let provider = MoyaProvider<Spreadsheets>()
    private let reloadQueue = DispatchQueue(label: "com.ianyh.Castle.reload")
    private static let spreadsheetID = "16K1Zryyxrh7vdKVF1f7eRrUAOC5wuzvC3q2gFLch6LQ"
    private static let ignoredSheets = ["Header", "Calculator", "Experience"]
    
    func reload() -> Observable<Void> {
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
                                realm.deleteAll()
                            }
                            try realm.write {
                                realm.add(sheets)
                            }
                        }
                    )
                    .map { _ in }
            }
    }
    
    func object(for sheet: Sheet, responses: (Response, Response)) throws -> SpreadsheetObject {
        let response = responses.0
        let rawResponse = responses.1
        let values = try JSONDecoder().decode(SheetsValues.self, from: response.data)
        let rawValues = try JSONDecoder().decode(SheetsRawValues.self, from: rawResponse.data)
        let headers = values.rows[0]
        let frozenColumnCount = sheet.properties.gridProperties.frozenColumnCount ?? 0
        
        let indexingColumns = (0..<frozenColumnCount).compactMap { index -> IndexingColumn? in
            let value = headers[index]
            
            guard value != "Img" else {
                return nil
            }

            let indexingColumn = IndexingColumn()
            indexingColumn.key = "\(sheet.properties.id)-\(value)"
            indexingColumn.title = value
            return indexingColumn
        }
        let indexedNameColumn = indexingColumns.first { $0.title == "Name" }
        let otherIndexedColumns = indexingColumns.filter { $0 != indexedNameColumn }
        let sortedIndexingColumns = indexedNameColumn.flatMap { [$0] + otherIndexedColumns } ?? otherIndexedColumns
        
        let rows = zip(values.rows[1...], rawValues.rows[1...]).map { (row, rawRow) -> Row in
            let rowObject = Row()
            let rowValues = zip(row, rawRow).prefix(headers.count).enumerated().map { (index, value) -> RowValue in
                let normalized = value.1
                var imageURL: String? = nil
                
                if case let .some(normalized) = normalized {
                    let imageURLStartRange = normalized.lowercased().range(of: "=image(\"")
                    let imageURLEndRange = normalized.lowercased().range(of: "\")") ?? normalized.lowercased().range(of: "\";")

                    if let startRange = imageURLStartRange, let endRange = imageURLEndRange {
                        imageURL = String(normalized[startRange.upperBound..<endRange.lowerBound])
                    }
                }
                
                let rowValue = RowValue()
                rowValue.key = "\(sheet.properties.id)-\(headers[index])"
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
        sheetObject.indexingColumns.append(objectsIn: sortedIndexingColumns)
        sheetObject.rows.append(objectsIn: rows)
        
        return sheetObject
    }
}
