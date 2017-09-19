//
//  AppDelegate.swift
//  Castle
//
//  Created by Ian Ynda-Hummel on 9/19/17.
//  Copyright © 2017 Ian Ynda-Hummel. All rights reserved.
//

import Moya
import RealmSwift
import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, UISplitViewControllerDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
        Realm.Configuration.defaultConfiguration.deleteRealmIfMigrationNeeded = true

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
        
        let settingsViewController = SettingsViewController()
        let settingsNavigationController = UINavigationController(rootViewController: settingsViewController)
        
        settingsNavigationController.tabBarItem = UITabBarItem(
            title: "Settings",
            image: UIImage(named: "settings"),
            selectedImage: UIImage(named: "settings-selected")
        )

        tabBarController.viewControllers = [splitViewController, settingsNavigationController]
        
        return true
    }
}
