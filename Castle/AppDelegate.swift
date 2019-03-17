//
//  AppDelegate.swift
//  Castle
//
//  Created by Ian Ynda-Hummel on 9/19/17.
//  Copyright © 2017 Ian Ynda-Hummel. All rights reserved.
//

import Kingfisher
import Moya
import RealmSwift
import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, UISplitViewControllerDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        Realm.Configuration.defaultConfiguration.deleteRealmIfMigrationNeeded = true
        
        ImageCache.default.diskStorage.config.expiration = .never
        ImageCache.default.diskStorage.config.sizeLimit = 0

        let tabBarController = window!.rootViewController as! UITabBarController
        let splitViewController = UISplitViewController()
        let sheetsViewController = SheetsListViewController()

        splitViewController.tabBarItem = UITabBarItem(
            title: "Archive",
            image: UIImage(named: "categories"),
            selectedImage: UIImage(named: "categories-selected")
        )
        splitViewController.viewControllers = [UINavigationController(rootViewController: sheetsViewController)]
        splitViewController.preferredDisplayMode = .allVisible
        
        let searchViewController = SearchViewController()
        
        searchViewController.tabBarItem = UITabBarItem(title: "Search", image: nil, selectedImage: nil)
        
        let settingsViewController = SettingsViewController()
        let settingsNavigationController = UINavigationController(rootViewController: settingsViewController)
        
        settingsNavigationController.tabBarItem = UITabBarItem(
            title: "Settings",
            image: UIImage(named: "settings"),
            selectedImage: UIImage(named: "settings-selected")
        )

        tabBarController.viewControllers = [splitViewController, searchViewController, settingsNavigationController]
        
        return true
    }
}
