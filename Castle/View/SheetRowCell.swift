//
//  SheetRowCell.swift
//  Castle
//
//  Created by Ian Ynda-Hummel on 3/21/18.
//  Copyright © 2018 Ian Ynda-Hummel. All rights reserved.
//

import Anchorage
import UIKit

class SheetRowCell: UITableViewCell {
    let titleLabel = UILabel()
    let valueLabel = UILabel()
    
    var isColumnFrozen: Bool = false {
        didSet {
            titleLabel.textAlignment = isColumnFrozen ? .center : .left
            titleLabel.font = .preferredFont(forTextStyle: .footnote)
            valueLabel.textAlignment = isColumnFrozen ? .center : .left
            valueLabel.font = isColumnFrozen ? .preferredFont(forTextStyle: .title3) : .preferredFont(forTextStyle: .body)
        }
    }
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        titleLabel.font = .preferredFont(forTextStyle: .caption1)
        titleLabel.numberOfLines = 0
        titleLabel.textColor = .lightGray
        
        valueLabel.font = .preferredFont(forTextStyle: .body)
        valueLabel.numberOfLines = 0
        
        contentView.addSubview(titleLabel)
        contentView.addSubview(valueLabel)
        
        titleLabel.leadingAnchor == contentView.safeAreaLayoutGuide.leadingAnchor + 16
        titleLabel.trailingAnchor == contentView.safeAreaLayoutGuide.trailingAnchor - 16
        titleLabel.topAnchor >= contentView.safeAreaLayoutGuide.topAnchor + 8
        titleLabel.bottomAnchor == valueLabel.topAnchor - 2
        
        valueLabel.leadingAnchor == contentView.safeAreaLayoutGuide.leadingAnchor + 16
        valueLabel.trailingAnchor == contentView.safeAreaLayoutGuide.trailingAnchor - 16
        valueLabel.centerYAnchor == contentView.safeAreaLayoutGuide.centerYAnchor + 6
        valueLabel.bottomAnchor <= contentView.safeAreaLayoutGuide.bottomAnchor - 8
        
        isColumnFrozen = false
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        accessoryType = .none
        isColumnFrozen = false
    }
}
