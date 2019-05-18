//
//  IconCell.swift
//  Castle
//
//  Created by Ian Ynda-Hummel on 5/17/19.
//  Copyright © 2019 Ian Ynda-Hummel. All rights reserved.
//

import Anchorage
import UIKit

class IconCell: UITableViewCell {
    let iconImageView = UIImageView()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        initializeViews()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func initializeViews() {
        iconImageView.contentMode = .scaleAspectFit
        contentView.addSubview(iconImageView)
        iconImageView.edgeAnchors == contentView.edgeAnchors + 8
    }
}
