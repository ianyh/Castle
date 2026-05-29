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
    /**
     Full `SpreadsheetRow` payloads for the rows in `results`, keyed by row id. Filled in by the search task after results are assigned, so taps that arrive after the preload completes navigate straight into `RowDetailView` without a `ProgressView` flash. Taps that arrive before the preload finishes fall through to `LazyRowDetailLoader`, which does the same one-row fetch on its own. Cleared whenever the query changes.
     */
    @State private var preloadedRows: [String: SpreadsheetRow] = [:]

    private static let searchableSheets = [
        "Characters",
        "Abilities",
        "Soul Breaks",
        "Limit Breaks",
        "Status",
        "Other",
        "Magicite",
        "Hero Abilities"
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
        .searchSuggestions {
            if searchText.isEmpty && !store.recentSearchRows.isEmpty {
                Section("Recent") {
                    ForEach(store.recentSearchRows, id: \.id) { row in
                        if let sheet = store.sheet(titled: row.spreadsheetTitle) {
                            NavigationLink {
                                RowDetailView(sheet: sheet, row: row)
                                    .task {
                                        await store.recordSearchTap(rowID: row.id, sheetTitle: row.spreadsheetTitle)
                                    }
                            } label: {
                                recentRowLabel(row)
                            }
                        }
                    }
                }
            }
        }
        .task(id: searchText) {
            guard searchText.count > 2 else {
                results = SearchResults(sections: [], rest: [])
                preloadedRows = [:]
                return
            }
            let sheets = SearchIndex.sheets(matchingPrefixIn: searchText) ?? Self.searchableSheets
            do {
                let searchResults = try await store.searchIndex.search(query: searchText, sheets: sheets)
                results = searchResults
                preloadedRows = [:]
                let allIDs = searchResults.sections.flatMap { $0.results.map(\.id) } + searchResults.rest.map(\.id)
                if !allIDs.isEmpty {
                    let rows = try await store.fetchRows(ids: allIDs)
                    preloadedRows = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
                }
            } catch {
                print("Search error: \(error)")
                results = SearchResults(sections: [], rest: [])
                preloadedRows = [:]
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
            if let sheet = store.sheet(titled: result.sheetTitle) {
                if let row = preloadedRows[result.id] {
                    RowDetailView(sheet: sheet, row: row)
                        .task {
                            await store.recordSearchTap(rowID: result.id, sheetTitle: result.sheetTitle)
                        }
                } else {
                    LazyRowDetailLoader(rowID: result.id, sheet: sheet, recordSearchTap: true)
                }
            }
        } label: {
            HStack(spacing: 12) {
                RowImage(url: result.imageURL, fallbackName: result.name)
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

    @ViewBuilder
    private func recentRowLabel(_ row: SpreadsheetRow) -> some View {
        HStack(spacing: 12) {
            let imageURLString = row.values.first(where: { $0.imageURL != nil })?.imageURL
            let imageURL = imageURLString.flatMap { URL(string: $0)?.cleaned() }
            RowImage(url: imageURL, fallbackName: row.normalizedName ?? "?")
            VStack(alignment: .leading, spacing: 2) {
                if let name = row.normalizedName {
                    Text(name).font(.body)
                }
                Text(row.spreadsheetTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
