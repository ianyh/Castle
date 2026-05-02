//
//  SpecialsView.swift
//
//  Created by Ian Ynda-Hummel on 12/24/23.
//  Copyright © 2023 Ian Ynda-Hummel. All rights reserved.
//

import SwiftUI

struct SpecialsView: View {
    @Environment(AppStore.self) private var store
    @State private var specialResults: [Special: [SearchResult]] = [:]
    @State private var isLoading: [Special: Bool] = [:]

    var body: some View {
        List {
            ForEach(Special.allCases, id: \.rawValue) { special in
                NavigationLink {
                    SearchResultsView(
                        results: specialResults[special] ?? [],
                        title: special.rawValue
                    )
                    .task {
                        await loadResults(for: special)
                    }
                } label: {
                    HStack {
                        Text(special.rawValue)
                        Spacer()
                        if isLoading[special] == true {
                            ProgressView()
                        }
                    }
                }
            }
        }
        .navigationTitle("Featured")
    }

    private func loadResults(for special: Special) async {
        guard specialResults[special] == nil else { return }
        isLoading[special] = true
        do {
            let statusIDs = special.statusIDs().map { "Status-\($0)" }
            let statusRows = try await store.fetchRows(dbIDs: statusIDs)
            let statusNames = statusRows.compactMap { $0.normalizedName }
            guard !statusNames.isEmpty else {
                specialResults[special] = []
                isLoading[special] = false
                return
            }

            let sheets = ["Soul Breaks", "Limit Breaks", "Other"]
            let matchQuery = statusNames
                .map { "content:\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
                .joined(separator: " OR ")

            specialResults[special] = try await store.searchIndex.searchEffects(
                matchQuery: matchQuery,
                sheets: sheets
            )
        } catch {
            print("Specials load error: \(error)")
            specialResults[special] = []
        }
        isLoading[special] = false
    }
}
