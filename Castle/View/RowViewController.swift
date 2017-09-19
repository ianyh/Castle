//
//  RowViewController.swift
//  Castle
//
//  Created by Ian Ynda-Hummel on 9/23/17.
//  Copyright © 2017 Ian Ynda-Hummel. All rights reserved.
//

import UIKit

class RowViewController: UITableViewController {
    class SubtitledCell: UITableViewCell {
        override init(style: UITableViewCellStyle, reuseIdentifier: String?) {
            super.init(style: .subtitle, reuseIdentifier: reuseIdentifier)
        }
        
        required init?(coder aDecoder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
    
    let row: Row
    
    init(row: Row) {
        self.row = row
        super.init(style: .plain)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        tableView.allowsSelection = false
        tableView.tableFooterView = UIView()
        tableView.register(SheetRowCell.self, forCellReuseIdentifier: "Cell")
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return row.values.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath) as! SheetRowCell
        let value = row.values[indexPath.section]
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
        return cell
    }
}
