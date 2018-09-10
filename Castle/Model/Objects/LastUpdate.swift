//
//  LastUpdate.swift
//  Castle
//
//  Created by Ian Ynda-Hummel on 9/9/18.
//  Copyright © 2018 Ian Ynda-Hummel. All rights reserved.
//

import Foundation
import RealmSwift

class LastUpdateObject: Object {
    @objc private dynamic var id = "LastUpdateObject"
    @objc private dynamic var date: Date!
    
    override static func primaryKey() -> String? {
        return "id"
    }
    
    static func lastUpdate() throws -> Date? {
        let realm = try Realm()
        return realm.object(ofType: LastUpdateObject.self, forPrimaryKey: "LastUpdateObject")?.date
    }
    
    static func markUpdate() throws {
        let realm = try Realm()
        let object = LastUpdateObject()
        object.id = "LastUpdateObject"
        object.date = Date()
        
        try realm.write {
            realm.add(object, update: true)
        }
    }
}
