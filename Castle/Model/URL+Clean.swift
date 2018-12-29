//
//  URL+Clean.swift
//  Castle
//
//  Created by Ian Ynda-Hummel on 12/29/18.
//  Copyright © 2018 Ian Ynda-Hummel. All rights reserved.
//

import Foundation

extension URL {
    func cleaned() -> URL {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: false)!
        components.scheme = "https"
        return components.url!
    }
}
