//
//  SettingsViewController.swift
//  Castle
//
//  Created by Ian Ynda-Hummel on 9/24/17.
//  Copyright © 2017 Ian Ynda-Hummel. All rights reserved.
//

import RealmSwift
import RxSwift
import UIKit

enum Row {
    case lastUpdate
    case sync
    case goToArchive
    case cacheImages
    case clearImageCache
    case empty
    
    var canSelect: Bool {
        switch self {
        case .lastUpdate, .empty:
            return false
        case .sync, .goToArchive, .cacheImages, .clearImageCache:
            return true
        }
    }
    
    var title: String? {
        switch self {
        case .lastUpdate, .sync, .goToArchive:
            return "Archive Data"
        case .cacheImages, .clearImageCache:
            return "Images"
        case .empty:
            return nil
        }
    }
    
    var footer: String? {
        switch self {
        case .lastUpdate, .sync, .goToArchive:
            return "Credit to the FFRK Community Database and its maintainers."
        case .cacheImages, .clearImageCache:
            return nil
        case .empty:
            return nil
        }
    }
    
    static var sectionCount: Int { return 3 }
    
    static func rowCount(forSection section: Int) -> Int {
        switch section {
        case 0:
            return 3
        case 1:
            return 0
        case 2:
            return 2
        default:
            return 0
        }
    }
    
    static func from(indexPath: IndexPath) -> Row {
        switch (indexPath.section, indexPath.row) {
        case (0, 0):
            return .lastUpdate
        case (0, 1):
            return .sync
        case (0, 2):
            return .goToArchive
        case (2, 0):
            return .cacheImages
        case (2, 1):
            return .clearImageCache
        default:
            return .empty
        }
    }
}

private class Cell: UITableViewCell {
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .value1, reuseIdentifier: reuseIdentifier)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        accessoryView = nil
        accessoryType = .none
    }
}

class SettingsViewController: UITableViewController {
    private let client = SpreadsheetsClient()
    private let disposeBag = DisposeBag()
    private let dateFormatter = DateFormatter()
    
    private var isReloading = false {
        didSet {
            tableView.reloadData()
        }
    }
    
    private var imageLoadProgress: String? = nil {
        didSet {
            tableView.reloadData()
        }
    }

    init() {
        super.init(style: .grouped)
        title = "Settings"
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        tableView.register(Cell.self, forCellReuseIdentifier: "Cell")
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return Row.sectionCount
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return Row.rowCount(forSection: section)
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        let row = Row.from(indexPath: indexPath)
        
        switch row {
        case .lastUpdate:
            cell.textLabel?.text = "Last update"
            cell.textLabel?.textColor = nil
            cell.detailTextLabel?.text = try! LastUpdateObject.lastUpdate().flatMap { dateFormatter.string(from: $0) }
            cell.selectionStyle = .none
        case .sync:
            cell.textLabel?.text = isReloading ? "Syncing" : "Sync"
            cell.textLabel?.textColor = isReloading ? .lightGray : .blue
            cell.detailTextLabel?.text = nil
            cell.selectionStyle = isReloading ? .none : .default
            if isReloading {
                let activityIndicator = UIActivityIndicatorView()
                activityIndicator.startAnimating()
                activityIndicator.sizeToFit()
                cell.accessoryView = activityIndicator
            }
        case .goToArchive:
            cell.textLabel?.text = "Go to archive"
            cell.textLabel?.textColor = nil
            cell.detailTextLabel?.text = nil
            cell.selectionStyle = .default
            cell.accessoryType = .disclosureIndicator
        case .cacheImages:
            cell.textLabel?.text = imageLoadProgress != nil ? "Downloading" : "Download images"
            cell.textLabel?.textColor = imageLoadProgress != nil ? .lightGray : .blue
            cell.detailTextLabel?.text = imageLoadProgress
            cell.selectionStyle = imageLoadProgress != nil ? .none : .default
        case .clearImageCache:
            cell.textLabel?.text = "Clear image cache"
            cell.textLabel?.textColor = .blue
            cell.detailTextLabel?.text = nil
            cell.selectionStyle = .default
        case .empty:
            break
        }
        
        return cell
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return Row.from(indexPath: IndexPath(row: 0, section: section)).title
    }
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return Row.from(indexPath: IndexPath(row: 0, section: section)).footer
    }
    
    override func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        return Row.from(indexPath: indexPath).canSelect ? indexPath : nil
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let row = Row.from(indexPath: indexPath)
        
        switch row {
        case .lastUpdate, .empty:
            break
        case .sync, .cacheImages:
            tableView.deselectRow(at: indexPath, animated: true)
            
            let alertController = UIAlertController(title: "Are you sure?", message: "This may take a while.", preferredStyle: .alert)
            let confirmAction = UIAlertAction(title: "Confirm", style: .destructive, handler: { [weak self] _ in
                switch row {
                case .sync:
                    self?.refreshData()
                case .cacheImages:
                    self?.loadImages()
                default:
                    return
                }
            })
            let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
            
            alertController.addAction(confirmAction)
            alertController.addAction(cancelAction)
            
            present(alertController, animated: true, completion: nil)
        case .goToArchive:
            let url = URL(string: "https://docs.google.com/spreadsheets/d/1f8OJIQhpycljDQ8QNDk_va1GJ1u7RVoMaNjFcHH0LKk/")!
            UIApplication.shared.open(url, options: [:]) { _ in
                tableView.deselectRow(at: indexPath, animated: true)
            }
        case .clearImageCache:
            tableView.deselectRow(at: indexPath, animated: true)
            client.clearImageCache()
        }
    }
    
    private func refreshData() {
        isReloading = true

        client.sync()
            .observeOn(MainScheduler.instance)
            .subscribe(
                onError: { [weak self] error in
                    self?.present(error: error)
                    self?.isReloading = false
                },
                onCompleted: { [weak self] in
                    self?.isReloading = false
                }
            )
            .disposed(by: disposeBag)
    }
    
    private func loadImages() {
        imageLoadProgress = ""
        
        client.preloadImages()
            .subscribe(
                onNext: { [weak self] progress in
                    self?.imageLoadProgress = progress
                },
                onError: { [weak self] error in
                    self?.present(error: error)
                    self?.imageLoadProgress = nil
                },
                onCompleted: { [weak self] in
                    self?.imageLoadProgress = nil
                }
            )
            .disposed(by: disposeBag)
    }
    
    private func present(error: Error) {
        let alertController = UIAlertController(title: "Error", message: error.localizedDescription, preferredStyle: .alert)
        let okAction = UIAlertAction(title: "OK", style: .cancel, handler: nil)
        
        alertController.addAction(okAction)
        
        present(alertController, animated: true, completion: nil)
    }
}
