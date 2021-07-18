//
//  LoadingCell.swift
//  Castle
//
//  Created by Ian Ynda-Hummel on 9/8/18.
//  Copyright © 2018 Ian Ynda-Hummel. All rights reserved.
//

import Anchorage
import UIKit

class LoadingCell: UITableViewCell {
    private let activityIndicatorView = UIActivityIndicatorView(style: .medium)
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        initializeViews()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func initializeViews() {
        contentView.addSubview(activityIndicatorView)
        activityIndicatorView.centerYAnchor == contentView.centerYAnchor
        activityIndicatorView.trailingAnchor == contentView.safeAreaLayoutGuide.trailingAnchor - 8
    }
    
    func startAnimating() {
        activityIndicatorView.startAnimating()
    }
}
