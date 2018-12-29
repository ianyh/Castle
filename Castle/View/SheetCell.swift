//
//  SheetCell.swift
//  Castle
//
//  Created by Ian Ynda-Hummel on 9/8/18.
//  Copyright © 2018 Ian Ynda-Hummel. All rights reserved.
//

import Anchorage
import Foundation
import UIKit

class SheetCell: UITableViewCell {
    private class ValueView: UIView {
        let titleLabel = UILabel()
        let valueLabel = UILabel()
        
        override init(frame: CGRect) {
            super.init(frame: frame)
            initializeViews()
        }
        
        required init?(coder aDecoder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        private func initializeViews() {
            titleLabel.font = .preferredFont(forTextStyle: .caption1)
            titleLabel.numberOfLines = 0
            titleLabel.textColor = .lightGray
            
            valueLabel.font = .preferredFont(forTextStyle: .body)
            valueLabel.numberOfLines = 0
            
            addSubview(titleLabel)
            addSubview(valueLabel)
            
            titleLabel.horizontalAnchors == safeAreaLayoutGuide.horizontalAnchors + 16
            titleLabel.trailingAnchor == safeAreaLayoutGuide.trailingAnchor - 16
            titleLabel.topAnchor >= safeAreaLayoutGuide.topAnchor + 8
            titleLabel.bottomAnchor == valueLabel.topAnchor - 2
            
            valueLabel.horizontalAnchors == safeAreaLayoutGuide.horizontalAnchors + 16
            valueLabel.centerYAnchor == safeAreaLayoutGuide.centerYAnchor + 6
            valueLabel.bottomAnchor <= safeAreaLayoutGuide.bottomAnchor - 8
        }
    }
    
    let titleLabel = UILabel()
    let valueLabel = UILabel()
    let iconImageView = UIImageView()
    private let stackView = UIStackView()
    
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
        
        stackView.axis = .vertical
        
        contentView.addSubview(iconImageView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(valueLabel)
        contentView.addSubview(stackView)
        
        iconImageView.widthAnchor == 50
        iconImageView.heightAnchor == 50
        leadingConstraint = (iconImageView.leadingAnchor == contentView.safeAreaLayoutGuide.leadingAnchor + 8)
        iconImageView.topAnchor == contentView.safeAreaLayoutGuide.topAnchor + 12
        
        titleLabel.leadingAnchor == iconImageView.trailingAnchor + 8
        titleLabel.trailingAnchor == contentView.safeAreaLayoutGuide.trailingAnchor - 16
        titleLabel.bottomAnchor == valueLabel.topAnchor - 2
        
        valueLabel.leadingAnchor == iconImageView.trailingAnchor + 8
        valueLabel.trailingAnchor == contentView.safeAreaLayoutGuide.trailingAnchor - 16
        valueLabel.centerYAnchor == iconImageView.centerYAnchor + 6
        
        stackView.topAnchor == iconImageView.bottomAnchor
        stackView.bottomAnchor == contentView.safeAreaLayoutGuide.bottomAnchor
        stackView.horizontalAnchors == contentView.safeAreaLayoutGuide.horizontalAnchors
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func set(valuePairs: [(String, String)]) {
        let views: [UIView] = valuePairs.map {
            let view = ValueView()
            view.titleLabel.text = $0.0
            view.valueLabel.text = $0.1
            return view
        }
        
        stackView.subviews.forEach { $0.removeFromSuperview() }
        views.forEach { stackView.addArrangedSubview($0) }
    }
}
