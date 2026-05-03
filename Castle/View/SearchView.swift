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
    @State private var results = SearchResults(sections: [], rest: [])

    private static let searchableSheets = [
        "Characters", "Abilities", "Soul Breaks",
        "Limit Breaks", "Status", "Other", "Magicite", "Hero Abilities"
    ]

    var body: some View {
        List {
            ForEach(results.sections, id: \.sheetTitle) { section in
                Section(section.sheetTitle) {
                    ForEach(section.results, id: \.id) { result in
                        resultRow(for: result, showSheetTitle: false)
                    }
                }
            }
            if !results.rest.isEmpty {
                Section {
                    ForEach(results.rest, id: \.id) { result in
                        resultRow(for: result, showSheetTitle: true)
                    }
                }
            }
        }
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search all sheets")
        .task(id: searchText) {
            guard searchText.count > 2 else {
                results = SearchResults(sections: [], rest: [])
                return
            }
            let sheets = SearchIndex.sheets(matchingPrefixIn: searchText) ?? Self.searchableSheets
            do {
                results = try await store.searchIndex.search(query: searchText, sheets: sheets)
            } catch {
                print("Search error: \(error)")
                results = SearchResults(sections: [], rest: [])
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(SearchIndex.prefixGroups, id: \.sheet) { group in
                        Section(group.sheet) {
                            ForEach(group.prefixes, id: \.self) { prefix in
                                Button(prefix.uppercased()) {
                                    searchText = "\(prefix) "
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
        }
    }

    @ViewBuilder
    private func resultRow(for result: SearchResult, showSheetTitle: Bool) -> some View {
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
                    if showSheetTitle {
                        Text(result.sheetTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        SearchView()
    }
    .environment(AppStore.preview)
}
#endif
