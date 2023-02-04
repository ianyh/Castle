//
//  RowViewController.swift
//  Castle
//
//  Created by Ian Ynda-Hummel on 9/23/17.
//  Copyright © 2017 Ian Ynda-Hummel. All rights reserved.
//

import CouchbaseLiteSwift
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
        super.init(style: .grouped)
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
    
    private func loadRelationships() {
        guard let normalizedName = row.normalizedName() else {
            return
        }
        
        let effect = row.effect()
        let normalizedSheetTitle = sheet.normalizedName()

        DispatchQueue.global(qos: .userInteractive).async {
            do {
                let database = try Database(name: "search")
                var relationExpression = Expression.property(normalizedSheetTitle).equalTo(Expression.string(normalizedName))
                
                if normalizedSheetTitle == "Soul Break" {
                    relationExpression = relationExpression.or(
                        Expression.property("Source").equalTo(Expression.string(normalizedName))
                    )
                }

                let query = QueryBuilder
                    .select(
                        SelectResult.expression(Meta.id),
                        SelectResult.property("_sheetTitle")
                    )
                    .from(DataSource.database(database))
                    .where(
                        relationExpression
                    )

                var relationships: [String: [String]] = [:]
                for result in try query.execute() {
                    let id = result.string(at: 0)!
                    let sheetTitle = result.string(at: 1)!
                    var sheetRelationships = relationships[sheetTitle] ?? []
                    sheetRelationships.append(id)
                    relationships[sheetTitle] = sheetRelationships
                }
                
                if let effect = effect {
                    let statusRegex = try NSRegularExpression(pattern: "\\[(.+?)\\]")
                    for match in statusRegex.matches(in: effect, range: NSMakeRange(0, effect.count)) {
                        let status = effect[Range(match.range(at: 1), in: effect)!]
                        let statusExpression = Expression.string(String(status))
                        let statusQuery = QueryBuilder
                            .select(
                                SelectResult.expression(Meta.id),
                                SelectResult.property("_sheetTitle")
                            )
                            .from(DataSource.database(database))
                            .where(
                                Expression.property("Common Name").equalTo(statusExpression)
                                    .or(Expression.property("Name").equalTo(statusExpression))
                            )
                        for result in try statusQuery.execute() {
                            let id = result.string(at: 0)!
                            let sheetTitle = result.string(at: 1)!
                            var sheetRelationships = relationships[sheetTitle] ?? []
                            sheetRelationships.append(id)
                            relationships[sheetTitle] = sheetRelationships
                        }
                    }
                    
                    let castRegex = try NSRegularExpression(pattern: "[Cc]asts (.+?) after")
                    for match in castRegex.matches(in: effect, range: NSMakeRange(0, effect.count)) {
                        let other = effect[Range(match.range(at: 1), in: effect)!]
                        let otherExpression = Expression.string(String(other))
                        let otherQuery = QueryBuilder
                            .select(SelectResult.expression(Meta.id))
                            .from(DataSource.database(database))
                            .where(Expression.property("_sheetTitle").equalTo(Expression.string("Other"))
                                .and(Expression.property("Name").equalTo(otherExpression))
                            )
                        for result in try otherQuery.execute() {
                            let id = result.string(at: 0)!
                            var sheetRelationships = relationships["Other"] ?? []
                            sheetRelationships.append(id)
                            relationships["Other"] = sheetRelationships
                        }
                    }
                }
                
                let flattenedRelationships = relationships.map { Relationship(title: $0, sheetID: $0, rowIDs: $1) }
                DispatchQueue.main.async {
                    self.relationships = flattenedRelationships.sorted { $0.title < $1.title }
                }
            } catch {
                print(error)
            }
        }
    }
}

extension RowViewController {
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 3
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let frozenCount = row.values.filter { $0.column?.isColumnFrozen ?? true }.count
        
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
        let frozenCount = row.values.filter { $0.column?.isColumnFrozen ?? true }.count
        
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
    
    private func cell(for value: RowValueObject, at indexPath: IndexPath, tableView: UITableView) -> UITableViewCell {
        let imageValue = value.imageURL.flatMap { URL(string: $0) }
        if let image = imageValue {
            let cell = tableView.dequeueReusableCell(withIdentifier: "Icon", for: indexPath) as! IconCell
            cell.selectionStyle = .none
            cell.iconImageView.kf.setImage(with: image)
            return cell
        } else {
            let cell = tableView.dequeueReusableCell(withIdentifier: "SheetRow", for: indexPath) as! SheetRowCell
            cell.selectionStyle = .none
            cell.isColumnFrozen = value.column?.isColumnFrozen ?? false
            cell.titleLabel.text = value.title
            cell.valueLabel.text = value.value
            return cell
        }
    }
}

extension RowViewController {
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard section == 1 && !relationships.isEmpty else {
            return nil
        }
        
        return "Relationships"
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
}
