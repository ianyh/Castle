//
//  SpreadsheetListView.swift
//
//  Created by Ian Ynda-Hummel on 9/19/17.
//  Copyright © 2017 Ian Ynda-Hummel. All rights reserved.
//

import SwiftUI

struct SpreadsheetListView: View {
    @Environment(AppStore.self) private var store
    @State private var searchText = ""
    @State private var searchResults: [SearchResult] = []

    var body: some View {
        List {
            ForEach(store.sheets, id: \.title) { sheet in
                NavigationLink(sheet.title) {
                    SpreadsheetView(sheet: sheet)
                }
            }
        }
        .navigationTitle("Archive")
        .searchable(text: $searchText, prompt: "Search all sheets")
        .task(id: searchText) {
            guard searchText.count > 2 else {
                searchResults = []
                return
            }
            do {
                let query = searchText
                let sheets = [
                    "Characters", "Abilities", "Soul Breaks",
                    "Limit Breaks", "Status", "Other", "Magicite", "Hero Abilities"
                ]
                searchResults = try await store.searchIndex.search(query: query, sheets: sheets)
            } catch {
                print("Search error: \(error)")
            }
        }
        .searchSuggestions {
            if searchText.count > 2 {
                ForEach(searchResults, id: \.id) { result in
                    NavigationLink {
                        LazyRowDetailLoader(rowID: result.id, sheetTitle: result.sheetTitle)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.name)
                            Text(result.sheetTitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .searchCompletion(result.name)
                }
            }
        }
    }
}
