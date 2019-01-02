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
    class SubtitledCell: UITableViewCell {
        override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
            super.init(style: .subtitle, reuseIdentifier: reuseIdentifier)
        }
        
        required init?(coder aDecoder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
    
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
        tableView.register(SheetRowCell.self, forCellReuseIdentifier: "Cell")
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
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath) as! SheetRowCell
        let frozenCount = row.values.filter { $0.column?.isFrozen ?? true }.count
        
        switch indexPath.section {
        case 0:
            fill(cell: cell, with: row.values[indexPath.row])
        case 1:
            let relationship = relationships[indexPath.row]
            cell.iconImageView.kf.cancelDownloadTask()
            cell.hasImage = false
            cell.titleLabel.text = relationship.title
            cell.valueLabel.text = nil
        case 2:
            fill(cell: cell, with: row.values[indexPath.row + frozenCount])
        default:
            break
        }

        return cell
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
    
    private func fill(cell: SheetRowCell, with value: RowValueObject) {
        let imageValue = value.imageURL.flatMap { URL(string: $0) }
        if let image = imageValue {
            cell.iconImageView.kf.setImage(with: image)
            cell.hasImage = true
            cell.titleLabel.text = nil
            cell.valueLabel.text = nil
        } else {
            cell.iconImageView.kf.cancelDownloadTask()
            cell.hasImage = false
            cell.titleLabel.text = value.title
            cell.valueLabel.text = value.value
        }
    }
    
    private func loadRelationships() {
        guard let normalizedName = row.values.first(where: { $0.column?.title.hasSuffix("Name") ?? false })?.value else {
            return
        }

        let normalizedSheetTitle = sheet.title.hasSuffix("s") ? String(sheet.title.dropLast()) : sheet.title

        DispatchQueue.global(qos: .userInteractive).async {
            let realm = try! Realm()
            let relatedSheets = realm.objects(SpreadsheetObject.self).filter("SUBQUERY(columns, $column, $column.title == %@).@count > 0", normalizedSheetTitle)
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
