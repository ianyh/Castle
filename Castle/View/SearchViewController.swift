//
//  SearchViewController.swift
//  Castle
//
//  Created by Ian Ynda-Hummel on 1/8/19.
//  Copyright © 2019 Ian Ynda-Hummel. All rights reserved.
//

import CouchbaseLiteSwift
import RealmSwift
import UIKit

private class Cell: UITableViewCell {
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .subtitle, reuseIdentifier: reuseIdentifier)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class SearchViewController: UITableViewController {
    private struct Row {
        let id: String
        let name: String
        let type: String
    }
    
    private var rows: [Row] = []
        
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(Cell.self, forCellReuseIdentifier: "Cell")
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return rows.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        let row = rows[indexPath.row]
        cell.textLabel?.text = row.name
        cell.detailTextLabel?.text = row.type
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let row = rows[indexPath.row]
        do {
            let realm = try Realm()
            
            guard let rowObject = realm.object(ofType: RowObject.self, forPrimaryKey: row.id) else {
                return
            }
            guard let spreadsheetObject = realm.object(ofType: SpreadsheetObject.self, forPrimaryKey: row.type) else {
                return
            }
            
            let rowViewController = RowViewController(sheet: spreadsheetObject, row: rowObject)
            parent?.presentingViewController?.navigationController?.pushViewController(rowViewController, animated: true)
        } catch {
            print(error)
        }
    }
}

extension SearchViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        guard let text = searchController.searchBar.text, text.count > 2 else {
            self.rows = []
            tableView.reloadData()
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            defer {
                DispatchQueue.main.async {
                    self.tableView.reloadData()
                }
            }
            
            let database = try! Database(name: "search")
            let searchableSheets = [
                "Characters",
                "Abilities",
                "Soul Breaks",
                "Limit Breaks",
                "Status",
                "Other",
                "Magicite"
            ].map { Expression.string($0) }
            let fulltextSearch = FullTextExpression.index("search").match("(Name:'\(text)*') OR (Common Name:'\(text)*') OR '\(text)'")
            let query = QueryBuilder
                .select(
                    SelectResult.expression(Meta.id),
                    SelectResult.property("Name"),
                    SelectResult.property("Common Name"),
                    SelectResult.property("_sheetTitle")
                )
                .from(DataSource.database(database))
                .where(Expression.property("_sheetTitle").in(searchableSheets).and(fulltextSearch))
                .orderBy(Ordering.expression(FullTextFunction.rank("search")).descending())
                .limit(Expression.int(50))
            
            do {
                var rows: [Row] = []
                for result in try query.execute() {
                    guard let name = (result.string(at: 1) ?? result.string(at: 2)) else {
                        continue
                    }
                    rows.append(Row(id: result.string(at: 0)!, name: name, type: result.string(at: 3)!))
                }
                
                self.rows = rows
            } catch {
                print(error)
            }
        }
    }
}
