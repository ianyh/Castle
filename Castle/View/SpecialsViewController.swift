//
//  SpecialsViewController.swift
//  Castle
//
//  Created by Ian Ynda-Hummel on 12/24/23.
//  Copyright © 2023 Ian Ynda-Hummel. All rights reserved.
//

import CouchbaseLiteSwift
import RealmSwift
import UIKit

class SpecialsViewController: UITableViewController {
    private lazy var realm = try! Realm()
        
    init() {
        super.init(style: .plain)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "Featured"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
    }

    // MARK: - Table View
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return Special.allCases.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        let special = Special.allCases[indexPath.row]
        cell.textLabel?.text = special.rawValue
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let special = Special.allCases[indexPath.row]
        let statusIDs = special.statusIDs().map { "Status-\($0)" }
        let statusRows = Array(realm.objects(RowObject.self).filter("dbID IN %@", statusIDs))
        let statusQuery = statusRows.compactMap { $0.normalizedName() }.map { "(Effects:'*[\($0)]*')" }.joined(separator: " OR ")
        var rows: [SearchViewController.Row] = []
        
        do {
            let database = try Database(name: "search")
            let searchableSheets = [
                "Soul Breaks",
                "Limit Breaks",
                "Other"
            ].map { Expression.string($0) }
            let index = Expression.fullTextIndex("searchIndex")
            let search = FullTextFunction.match(index, query: statusQuery)
            let query = QueryBuilder
                .select(
                    SelectResult.expression(Meta.id),
                    SelectResult.property("Name"),
                    SelectResult.property("Common Name"),
                    SelectResult.property("_sheetTitle"),
                    SelectResult.property("_imageURL")
                )
                .from(try DataSource.collection(database.defaultCollection()))
                .where(Expression.property("_sheetTitle").in(searchableSheets).and(search))
                .orderBy(Ordering.expression(FullTextFunction.rank(index)).descending())

            for result in try query.execute() {
                guard let name = (result.string(at: 1) ?? result.string(at: 2)) else {
                    continue
                }

                let imageURL = result.string(at: 4).flatMap { URL(string: $0) }
                rows.append(SearchViewController.Row(id: result.string(at: 0)!, name: name, type: result.string(at: 3)!, imageURL: imageURL))
            }
        } catch {
            print(error)
        }
        
        let searchViewController = SearchViewController(rows: rows)
        searchViewController.navigationItem.title = special.rawValue
        navigationController?.pushViewController(searchViewController, animated: true)
    }
}
