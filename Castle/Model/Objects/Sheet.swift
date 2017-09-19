//
//  Sheet.swift
//  Castle
//
//  Created by Ian Ynda-Hummel on 9/1/18.
//  Copyright © 2018 Ian Ynda-Hummel. All rights reserved.
//

import Foundation
import RealmSwift

class SpreadsheetObject: Object {
    @objc dynamic var title: String = ""
    let indexingColumns = List<IndexingColumn>()
    let rows = List<Row>()
}

class RowValue: Object {
    @objc dynamic var key: String = ""
    @objc dynamic var title: String = ""
    @objc dynamic var value: String = ""
    @objc dynamic var imageURL: String?
}

class Row: Object {
    let values = List<RowValue>()
}

class IndexingColumn: Object {
    @objc dynamic var key: String = ""
    @objc dynamic var title: String = ""
    
    override static func primaryKey() -> String? {
        return "key"
    }
}
