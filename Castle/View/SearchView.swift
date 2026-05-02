//
//  SearchView.swift
//
//  Created by Ian Ynda-Hummel on 5/1/26.
//  Copyright © 2026 Ian Ynda-Hummel. All rights reserved.
//

import Kingfisher
import SwiftUI

struct SearchView: View {
    @Environment(AppStore.self) private var store
    @State private var searchText = ""
    @State private var results: [SearchResult] = []

    private static let searchableSheets = [
        "Characters", "Abilities", "Soul Breaks",
        "Limit Breaks", "Status", "Other", "Magicite", "Hero Abilities"
    ]

    var body: some View {
        List(results, id: \.id) { result in
            NavigationLink {
                LazyRowDetailLoader(rowID: result.id, sheetTitle: result.sheetTitle)
            } label: {
                HStack(spacing: 12) {
                    if let imageURL = result.imageURL {
                        KFImage(imageURL)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 44, height: 44)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.name)
                            .font(.body)
                        Text(result.sheetTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Search")
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search all sheets")
        .task(id: searchText) {
            guard searchText.count > 2 else {
                results = []
                return
            }
            do {
                results = try await store.searchIndex.search(query: searchText, sheets: Self.searchableSheets)
            } catch {
                print("Search error: \(error)")
                results = []
            }
        }
    }
}
