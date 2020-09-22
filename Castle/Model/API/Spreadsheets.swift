//
//  Spreadsheets.swift
//  Castle
//
//  Created by Ian Ynda-Hummel on 9/20/17.
//  Copyright © 2017 Ian Ynda-Hummel. All rights reserved.
//

import Foundation

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
