//
//  Specials.swift
//  Castle
//
//  Created by Ian Ynda-Hummel on 12/24/23.
//  Copyright © 2023 Ian Ynda-Hummel. All rights reserved.
//

import Foundation

enum Special: String, CaseIterable {
    case aegisBreak = "Aegis Break"
    case fullBreakCounter = "Full Break Counter"
    case jobBreakCounter = "Job Break Counter"
    
    func statusIDs() -> [String] {
        switch self {
        case .aegisBreak:
            return [
                "646033",
                "646111",
                "646121",
                "646131",
                "646141"
            ]
        case .fullBreakCounter:
            return [
                "6053",
                "6067"
            ]
        case .jobBreakCounter:
            return [
                "6054",
                "6056",
                "6057"
            ]
        }
    }
}
