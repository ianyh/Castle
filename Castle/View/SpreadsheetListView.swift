//
//  SpreadsheetListView.swift
//
//  Created by Ian Ynda-Hummel on 9/19/17.
//  Copyright © 2017 Ian Ynda-Hummel. All rights reserved.
//

import SwiftUI

struct SpreadsheetListView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        List {
            ForEach(store.sheets, id: \.title) { sheet in
                NavigationLink(sheet.title) {
                    SpreadsheetView(sheet: sheet)
                }
            }
        }
        .navigationTitle("Archive")
    }
}
