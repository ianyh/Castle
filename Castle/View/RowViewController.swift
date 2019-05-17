//
//  RowViewController.swift
//  Castle
//
//  Created by Ian Ynda-Hummel on 9/23/17.
//  Copyright © 2017 Ian Ynda-Hummel. All rights reserved.
//

import RealmSwift
import UIKit

private struct Relationship {
    let title: String
    let sheetID: String
    let rowIDs: [String]
}

class RowViewController: UITableViewController {
    let sheet: SpreadsheetObject
    let row: RowObject
    
    private var relationships: [Relationship] = [] {
        didSet {
            tableView?.reloadData()
        }
    }
    
    init(sheet: SpreadsheetObject, row: RowObject) {
        self.sheet = sheet
        self.row = row
        super.init(style: .plain)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        tableView.allowsSelection = true
        tableView.tableFooterView = UIView()
        tableView.register(IconCell.self, forCellReuseIdentifier: "Icon")
        tableView.register(SheetRowCell.self, forCellReuseIdentifier: "SheetRow")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        loadRelationships()
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 3
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let frozenCount = row.values.filter { $0.column?.isFrozen ?? true }.count
        
        switch section {
        case 0:
            return frozenCount
        case 1:
            return relationships.count
        case 2:
            return row.values.count - frozenCount
        default:
            return 0
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let frozenCount = row.values.filter { $0.column?.isFrozen ?? true }.count
        
        switch indexPath.section {
        case 0:
            return cell(for: row.values[indexPath.row], at: indexPath, tableView: tableView)
        case 1:
            let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
            let relationship = relationships[indexPath.row]
            cell.accessoryType = .disclosureIndicator
            cell.textLabel?.text = relationship.title
            return cell
        case 2:
            return cell(for: row.values[indexPath.row + frozenCount], at: indexPath, tableView: tableView)
        default:
            fatalError()
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch indexPath.section {
        case 0, 2:
            return
        case 1:
            let relationship = relationships[indexPath.row]
            let realm = try! Realm()
            let sheet = realm.object(ofType: SpreadsheetObject.self, forPrimaryKey: relationship.sheetID)!
            let rows = Array(realm.objects(RowObject.self).filter("id IN %@", relationship.rowIDs))
            let sheetViewController = SheetViewController(sheet: sheet, explicitRows: rows)
            navigationController?.pushViewController(sheetViewController, animated: true)
        default:
            return
        }
    }
    
    override func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        guard indexPath.section == 1 else {
            return nil
        }
        
        return indexPath
    }
    
    private func cell(for value: RowValueObject, at indexPath: IndexPath, tableView: UITableView) -> UITableViewCell {
        let imageValue = value.imageURL.flatMap { URL(string: $0) }
        if let image = imageValue {
            let cell = tableView.dequeueReusableCell(withIdentifier: "Icon", for: indexPath) as! IconCell
            cell.iconImageView.kf.setImage(with: image)
            return cell
        } else {
            let cell = tableView.dequeueReusableCell(withIdentifier: "SheetRow", for: indexPath) as! SheetRowCell
            cell.isFrozen = value.column?.isFrozen ?? false
            cell.titleLabel.text = value.title
            cell.valueLabel.text = value.value
            return cell
        }
    }
    
    private func loadRelationships() {
        guard let normalizedName = row.normalizedName() else {
            return
        }

        let normalizedSheetTitle = sheet.normalizedName()

        DispatchQueue.global(qos: .userInteractive).async {
            let realm = try! Realm()
            let relatedSheets = realm
                .objects(SpreadsheetObject.self)
                .filter("SUBQUERY(columns, $column, $column.title == %@).@count > 0", normalizedSheetTitle)
            let relationships = Array(relatedSheets.map { relatedSheet -> Relationship in
                let relatedRows = relatedSheet.rows.filter { row in
                    return row.values.first { $0.column?.title == normalizedSheetTitle && $0.value == normalizedName } != nil
                }
                let rowIDs = relatedRows.map { $0.id }
                return Relationship(title: relatedSheet.title, sheetID: relatedSheet.title, rowIDs: Array(rowIDs))
            })
            
            DispatchQueue.main.async {
                self.relationships = relationships
            }
        }
    }
}
