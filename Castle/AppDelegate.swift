//
//  AppDelegate.swift
//  Castle
//
//  Created by Ian Ynda-Hummel on 9/19/17.
//  Copyright © 2017 Ian Ynda-Hummel. All rights reserved.
//

import Kingfisher
import RealmSwift
import RxSwift
import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, UISplitViewControllerDelegate {
    var window: UIWindow?
    
    private let client = SpreadsheetsClient()
    private let disposeBag = DisposeBag()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        Realm.Configuration.defaultConfiguration.deleteRealmIfMigrationNeeded = true
        
        ImageCache.default.diskStorage.config.expiration = .never
        ImageCache.default.diskStorage.config.sizeLimit = 0

        let tabBarController = window!.rootViewController!.children[0] as! UITabBarController
        
        let sheetsViewController = SheetsListViewController()
        let sheetsNavigationController = UINavigationController(rootViewController: sheetsViewController)

        sheetsNavigationController.tabBarItem = UITabBarItem(
            title: "Archive",
            image: UIImage(named: "categories"),
            selectedImage: UIImage(named: "categories-selected")
        )
        
        let settingsViewController = SettingsViewController()
        let settingsNavigationController = UINavigationController(rootViewController: settingsViewController)
        
        settingsNavigationController.tabBarItem = UITabBarItem(
            title: "Settings",
            image: UIImage(named: "settings"),
            selectedImage: UIImage(named: "settings-selected")
        )
        
        let specialsViewController = SpecialsViewController()
        let specialsNavigationController = UINavigationController(rootViewController: specialsViewController)
        
        specialsNavigationController.tabBarItem = UITabBarItem(title: "Specials", image: nil, selectedImage: nil)

        tabBarController.viewControllers = [sheetsNavigationController, settingsNavigationController, specialsNavigationController]
        
        DispatchQueue.main.async {
            guard (try? LastUpdateObject.lastUpdate()) == nil else {
                return
            }
            
            self.presentFirstTimeSync()
        }
        
        return true
    }
    
    private func presentFirstTimeSync() {
        let alertController = UIAlertController(title: nil, message: "Looks like this is your first time in the app. We need to sync the database to get you started.", preferredStyle: .alert)
        let confirmAction = UIAlertAction(title: "Sync", style: .default) { [weak self] _ in
            guard let `self` = self else {
                return
            }
    
            self.client.sync().subscribe().disposed(by: self.disposeBag)
        }
        
        alertController.addAction(confirmAction)
        
        window?.rootViewController?.present(alertController, animated: true, completion: nil)
    }
}
