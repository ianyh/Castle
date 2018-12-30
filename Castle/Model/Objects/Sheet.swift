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
    let columns = List<ColumnObject>()
    let rows = List<RowObject>()
    
    var frozenColumns: Results<ColumnObject> {
        return columns.filter("isFrozen == true")
    }
    
    override static func primaryKey() -> String? {
        return "title"
    }
}

class ColumnObject: Object {
    @objc dynamic var key: String = ""
    @objc dynamic var isFrozen: Bool = false
    @objc dynamic var title: String = ""
    
    override static func primaryKey() -> String? {
        return "key"
    }
}

class RowValueObject: Object {
    @objc dynamic var id: String = ""
    @objc dynamic var column: ColumnObject?
    @objc dynamic var title: String = ""
    @objc dynamic var value: String = ""
    @objc dynamic var imageURL: String?
    
    override static func primaryKey() -> String? {
        return "id"
    }
}

class RowObject: Object {
    @objc dynamic var id: String = ""
    let values = List<RowValueObject>()
    
    override static func primaryKey() -> String? {
        return "id"
    }
}
