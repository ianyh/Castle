//
//  SheetsListViewController.swift
//  Castle
//
//  Created by Ian Ynda-Hummel on 9/19/17.
//  Copyright © 2017 Ian Ynda-Hummel. All rights reserved.
//

import Moya
import RealmSwift
import UIKit

class SheetsListViewController: UITableViewController {
    lazy var realm: Realm = {
        return try! Realm()
    }()
    lazy var sheets: Results<SpreadsheetObject> = {
        return self.realm.objects(SpreadsheetObject.self).sorted(byKeyPath: "title")
    }()
    
    var sheetObjects: [SpreadsheetObject] = [] {
        didSet {
            tableView.reloadData()
        }
    }
    var token: NotificationToken?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "Archive"

        token = sheets.observe { results in
            switch results {
            case let .initial(sheets):
                self.sheetObjects = Array(sheets)
            case let .update(sheets, _, _, _):
                self.sheetObjects = Array(sheets)
            case let .error(error):
                print(error)
            }
        }

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
    }

    // MARK: - Table View
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sheetObjects.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        
        let sheet = sheetObjects[indexPath.row]
        cell.textLabel!.text = sheet.title
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let sheet = sheetObjects[indexPath.row]
        let sheetViewController = SheetViewController(sheet: sheet)

        navigationController?.pushViewController(sheetViewController, animated: true)
    }
}
