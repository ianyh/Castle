//
//  Spreadsheets.swift
//  Castle
//
//  Created by Ian Ynda-Hummel on 9/20/17.
//  Copyright © 2017 Ian Ynda-Hummel. All rights reserved.
//

import Foundation
import Moya

enum RawValue: Decodable {
    case some(String)
    case none
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            let value = try container.decode(String.self)
            self = .some(value)
        } catch {
            self = .none
        }
    }
}

struct SheetGridProperties: Decodable {
    let rowCount: Int
    let columnCount: Int
    let frozenRowCount: Int?
    let frozenColumnCount: Int?
}

struct SheetProperties: Decodable {
    let id: Int
    let title: String
    let gridProperties: SheetGridProperties
    
    enum CodingKeys: String, CodingKey {
        case id = "sheetId"
        case title
        case gridProperties
    }
}

struct Sheet: Decodable {
    let properties: SheetProperties
}

struct Spreadsheet: Decodable {
    let sheets: [Sheet]
}

struct SpreadsheetValues: Decodable {
    let ranges: [SpreadsheetRange]
    
    enum CodingKeys: String, CodingKey {
        case ranges = "valueRanges"
    }
}

struct SpreadsheetRawValues: Decodable {
    let ranges: [SpreadsheetRawRange]
    
    enum CodingKeys: String, CodingKey {
        case ranges = "valueRanges"
    }
}

struct SpreadsheetRange: Decodable {
    let range: String
    let rows: [[String]]
    
    enum CodingKeys: String, CodingKey {
        case range
        case rows = "values"
    }
}

struct SpreadsheetRawRange: Decodable {
    let range: String
    let rows: [[RawValue]]
    
    enum CodingKeys: String, CodingKey {
        case range
        case rows = "values"
    }
}

enum Spreadsheets: TargetType {
    case spreadsheets(spreadsheetID: String, key: String)
    case values(spreadsheetID: String, sheets: [Sheet], key: String, raw: Bool)
    
    var baseURL: URL {
        return URL(string: "https://sheets.googleapis.com")!
    }
    
    var path: String {
        switch self {
        case let .spreadsheets(spreadsheetID, _):
            return "/v4/spreadsheets/\(spreadsheetID)"
        case let .values(spreadsheetID, _, _, _):
            return "/v4/spreadsheets/\(spreadsheetID)/values:batchGet"
        }
    }
    
    var method: Moya.Method {
        return .get
    }
    
    var sampleData: Data {
        return Data()
    }
    
    var task: Task {
        switch self {
        case let .spreadsheets(_, key):
            return .requestParameters(parameters: ["fields": "sheets.properties", "key": key], encoding: URLEncoding.default)
        case let .values(_, sheets, key, raw):
            return .requestParameters(
                parameters: [
                    "ranges": sheets.map { $0.properties.title },
                    "valueRenderOption": raw ? "FORMULA" : "FORMATTED_VALUE",
                    "key": key
                ],
                encoding: URLEncoding(arrayEncoding: .noBrackets)
            )
        }
    }
    
    var headers: [String : String]? {
        return nil
    }
}
