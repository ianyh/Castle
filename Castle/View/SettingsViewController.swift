//
//  SettingsViewController.swift
//  Castle
//
//  Created by Ian Ynda-Hummel on 9/24/17.
//  Copyright © 2017 Ian Ynda-Hummel. All rights reserved.
//

import Moya
import RealmSwift
import RxSwift
import UIKit

private class Cell: UITableViewCell {
    override init(style: UITableViewCellStyle, reuseIdentifier: String?) {
        super.init(style: .value1, reuseIdentifier: reuseIdentifier)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
        tableView.register(LoadingCell.self, forCellReuseIdentifier: "LoadingCell")
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 3
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        
        switch indexPath.row {
        case 0:
            cell.textLabel?.text = "Last updated"
            cell.textLabel?.textColor = nil
            cell.detailTextLabel?.text = try! LastUpdateObject.lastUpdate().flatMap { dateFormatter.string(from: $0) }
            cell.selectionStyle = .none
        case 1:
            cell.textLabel?.text = isReloading ? "Syncing..." : "Sync from spreadsheet..."
            cell.textLabel?.textColor = isReloading ? .lightGray : .blue
            cell.detailTextLabel?.text = nil
            cell.selectionStyle = isReloading ? .none : .default
        case 2:
            cell.textLabel?.text = imageLoadProgress != nil ? "Loading..." : "Preload all images..."
            cell.textLabel?.textColor = imageLoadProgress != nil ? .lightGray : .blue
            cell.detailTextLabel?.text = imageLoadProgress
            cell.selectionStyle = imageLoadProgress != nil ? .none : .default
        default:
            break
        }
        
        return cell
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return "Archive Data"
    }
    
    override func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        guard indexPath.row > 0 else {
            return nil
        }
        
        switch indexPath.row {
        case 1:
            return isReloading ? nil : indexPath
        case 2:
            return imageLoadProgress != nil ? nil : indexPath
        default:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let alertController = UIAlertController(title: "Are you sure?", message: "This may take a while.", preferredStyle: .alert)
        let confirmAction = UIAlertAction(title: "Confirm", style: .destructive, handler: { [weak self] _ in
            switch indexPath.row {
            case 1:
                self?.refreshData()
            case 2:
                self?.loadImages()
            default:
                return
            }
        })
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
        
        alertController.addAction(confirmAction)
        alertController.addAction(cancelAction)

        present(alertController, animated: true, completion: nil)
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
