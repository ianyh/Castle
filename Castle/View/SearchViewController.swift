//
//  SearchViewController.swift
//  Castle
//
//  Created by Ian Ynda-Hummel on 1/8/19.
//  Copyright © 2019 Ian Ynda-Hummel. All rights reserved.
//

import UIKit

class SearchViewController: UIViewController {
    private var webView: UIWebView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        webView = UIWebView(frame: view.frame)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.translatesAutoresizingMaskIntoConstraints = true
        
        view.addSubview(webView)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        webView.loadRequest(URLRequest(url: URL(string: "https://sbs.jaryth.net/")!))
    }
}
