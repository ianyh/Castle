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

class SettingsViewController: UITableViewController {
    private let client = SpreadsheetsClient()
    private let disposeBag = DisposeBag()
    
    private var isLoading = false {
        didSet {
            tableView.reloadData()
        }
    }

    init() {
        super.init(style: .grouped)
        title = "Settings"
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        tableView.register(LoadingCell.self, forCellReuseIdentifier: "LoadingCell")
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard !isLoading else {
            let cell = tableView.dequeueReusableCell(withIdentifier: "LoadingCell", for: indexPath) as! LoadingCell
            cell.textLabel?.text = "Reloading..."
            cell.startAnimating()
            return cell
        }
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        cell.textLabel?.text = "Reload all data from spreadsheet..."
        cell.textLabel?.textColor = .blue
        return cell
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return "Archive Data"
    }

//    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
//        return "This will refresh all data from the spreadsheet."
//    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let alertController = UIAlertController(title: "Are you sure?", message: "The reload may take a while.", preferredStyle: .alert)
        let confirmAction = UIAlertAction(title: "Confirm", style: .destructive, handler: { [weak self] _ in
            self?.refreshData()
        })
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
        
        alertController.addAction(confirmAction)
        alertController.addAction(cancelAction)

        present(alertController, animated: true, completion: nil)
    }
    
    private func refreshData() {
        isLoading = true

        client.reload()
            .observeOn(MainScheduler.instance)
            .subscribe(
                onError: { [weak self] error in
                    self?.present(error: error)
                    self?.isLoading = false
                },
                onCompleted: { [weak self] in
                    self?.isLoading = false
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
