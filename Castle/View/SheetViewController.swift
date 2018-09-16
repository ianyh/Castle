//
//  SheetViewController.swift
//  Castle
//
//  Created by Ian Ynda-Hummel on 9/19/17.
//  Copyright © 2017 Ian Ynda-Hummel. All rights reserved.
//

import Anchorage
import Kingfisher
import RealmSwift
import UIKit

struct Filter {
    let columnFilters: [String: [String]]
}

class SheetViewController: UITableViewController {
    let sheet: SpreadsheetObject
    let searchController = UISearchController(searchResultsController: nil)

    private var filteredResults: Results<Row> {
        didSet {
            tableView?.reloadData()
        }
    }
    private var searchQuery: String? {
        didSet {
            updateFilters(searchQuery: searchQuery, filter: filter)
        }
    }
    private var filter: Filter? {
        didSet {
            updateFilters(searchQuery: searchQuery, filter: filter)
        }
    }

    init(sheet: SpreadsheetObject) {
        self.sheet = sheet
        self.filteredResults = sheet.rows.filter(NSPredicate(value: true))
        super.init(style: .grouped)
        hidesBottomBarWhenPushed = true
        navigationItem.hidesSearchBarWhenScrolling = false
        title = sheet.title
    }
    
    private func updateFilters(searchQuery: String?, filter: Filter?) {
        var filterPredicates: [NSPredicate] = []
        
        if let filter = filter {
            filterPredicates.append(contentsOf: filter.columnFilters.map { column -> NSPredicate in
                return NSPredicate(
                    format: "SUBQUERY(values, $value, $value.key == %@ AND $value.value in %@).@count > 0",
                    column.key,
                    column.value
                )
            })
        }
        
        if let query = searchQuery {
            let index = sheet.indexingColumns.count > 1 ? searchController.searchBar.selectedScopeButtonIndex : 0
            filterPredicates.append(NSPredicate(
                format: "SUBQUERY(values, $value, $value.key == %@ AND $value.value CONTAINS[c] %@).@count > 0",
                sheet.indexingColumns[index].key,
                query
            ))
        }
        
        filteredResults = filterPredicates.reduce(sheet.rows.filter(NSPredicate(value: true))) { results, predicate -> Results<Row> in
            return results.filter(predicate)
        }
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        tableView.estimatedRowHeight = 50
        tableView.keyboardDismissMode = .interactive
        tableView.rowHeight = UITableViewAutomaticDimension
        tableView.separatorStyle = .singleLine
        tableView.register(SheetCell.self, forCellReuseIdentifier: "Cell")
        
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.delegate = self
        searchController.searchBar.scopeButtonTitles = sheet.indexingColumns.count > 1 ? sheet.indexingColumns.map { $0.title } : []
        navigationItem.searchController = searchController
        definesPresentationContext = true
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationItem.searchController?.searchBar.resignFirstResponder()
    }

    // MARK: - Table View

    override func numberOfSections(in tableView: UITableView) -> Int {
        return filteredResults.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath) as! SheetCell
        let imageValue = filteredResults[indexPath.section].values.first { $0.imageURL != nil }?.imageURL.flatMap { URL(string: $0) }
        let indexedRowValues = sheet.indexingColumns.map { column in
            return self.filteredResults[indexPath.section].values.filter("key == %@", column.key).first!
        }
        let primaryRowValue = indexedRowValues[0]
        cell.titleLabel.text = primaryRowValue.title
        cell.valueLabel.text = primaryRowValue.value
        cell.accessoryType = indexPath.row == 0 ? .disclosureIndicator : .none
        cell.set(valuePairs: indexedRowValues.dropFirst().map { ($0.title, $0.value) })
        
        if indexPath.row == 0, let image = imageValue {
            cell.iconImageView.kf.setImage(with: image)
            cell.hasImage = true
        } else {
            cell.iconImageView.kf.cancelDownloadTask()
            cell.hasImage = false
        }
        
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let row = filteredResults[indexPath.section]
        let rowViewController = RowViewController(row: row)
        
        splitViewController?.showDetailViewController(rowViewController, sender: self)
    }
}

extension SheetViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, selectedScopeButtonIndexDidChange selectedScope: Int) {
        updateFilters(searchQuery: searchQuery, filter: filter)
    }
}

extension SheetViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        searchQuery = searchController.searchBar.text.flatMap { $0.isEmpty ? nil : $0 }
    }
}