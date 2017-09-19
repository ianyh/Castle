//
//  Spreadsheets.swift
//  Castle
//
//  Created by Ian Ynda-Hummel on 9/20/17.
//  Copyright © 2017 Ian Ynda-Hummel. All rights reserved.
//

import Foundation
import Moya

struct SheetsValues: Decodable {
    let rows: [[String]]
    
    enum CodingKeys: String, CodingKey {
        case rows = "values"
    }
}

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

struct SheetsRawValues: Decodable {
    let rows: [[RawValue]]
    
    enum CodingKeys: String, CodingKey {
        case rows = "values"
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

enum Spreadsheets: TargetType {
    case spreadsheets(spreadsheetID: String, key: String)
    case values(spreadsheetID: String, sheet: Sheet, key: String, raw: Bool)
    
    var baseURL: URL {
        return URL(string: "https://sheets.googleapis.com")!
    }
    
    var path: String {
        switch self {
        case let .spreadsheets(spreadsheetID, _):
            return "/v4/spreadsheets/\(spreadsheetID)"
        case let .values(spreadsheetID, sheet, _, _):
            return "/v4/spreadsheets/\(spreadsheetID)/values/\(sheet.properties.title)"
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
            return .requestParameters(parameters: ["key": key], encoding: URLEncoding.default)
        case let .values(_, _, key, raw):
            let renderOption = raw ? "FORMULA" : "FORMATTED_VALUE"
            return .requestParameters(parameters: ["valueRenderOption": renderOption, "key": key], encoding: URLEncoding.default)
        }
    }
    
    var headers: [String : String]? {
        return nil
    }
}
