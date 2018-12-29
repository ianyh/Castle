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
    let iconImageView = UIImageView()
    let titleLabel = UILabel()
    let valueLabel = UILabel()
    
    var hasImage: Bool = true {
        didSet {
            iconImageView.isHidden = !hasImage
            leadingConstraint?.constant = hasImage ? 8 : -42
            
            verticalConstraintPair?.first.isActive = hasImage
            verticalConstraintPair?.second.isActive = hasImage
        }
    }
    private var leadingConstraint: NSLayoutConstraint?
    private var verticalConstraintPair: ConstraintPair?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        titleLabel.font = .preferredFont(forTextStyle: .caption1)
        titleLabel.numberOfLines = 0
        titleLabel.textColor = .lightGray
        
        valueLabel.font = .preferredFont(forTextStyle: .body)
        valueLabel.numberOfLines = 0
        
        contentView.addSubview(iconImageView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(valueLabel)
        
        iconImageView.widthAnchor == 50
        iconImageView.heightAnchor == 50
        iconImageView.centerYAnchor == contentView.safeAreaLayoutGuide.centerYAnchor
        leadingConstraint = (iconImageView.leadingAnchor == contentView.safeAreaLayoutGuide.leadingAnchor + 8)
        verticalConstraintPair = (iconImageView.verticalAnchors >= contentView.safeAreaLayoutGuide.verticalAnchors + 12)
        
        titleLabel.leadingAnchor == iconImageView.trailingAnchor + 8
        titleLabel.trailingAnchor == contentView.safeAreaLayoutGuide.trailingAnchor - 16
        titleLabel.topAnchor >= contentView.safeAreaLayoutGuide.topAnchor + 8
        titleLabel.bottomAnchor == valueLabel.topAnchor - 2
        
        valueLabel.leadingAnchor == iconImageView.trailingAnchor + 8
        valueLabel.trailingAnchor == contentView.safeAreaLayoutGuide.trailingAnchor - 16
        valueLabel.centerYAnchor == contentView.safeAreaLayoutGuide.centerYAnchor + 6
        valueLabel.bottomAnchor <= contentView.safeAreaLayoutGuide.bottomAnchor - 8
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
