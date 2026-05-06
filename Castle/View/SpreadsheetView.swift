//
//  SpreadsheetView.swift
//
//  Created by Ian Ynda-Hummel on 9/19/17.
//  Copyright © 2017 Ian Ynda-Hummel. All rights reserved.
//

import Kingfisher
import SwiftUI

struct SpreadsheetView: View {
    let sheet: Spreadsheet
    var explicitRows: [SpreadsheetRow] = []

    @Environment(AppStore.self) private var store
    @State private var allRows: [SpreadsheetRow] = []
    @State private var searchText = ""
    @State private var selectedScope = 0

    private var frozenColumns: [SpreadsheetColumn] {
        sheet.frozenColumns
    }

    private var scopeTitles: [String] {
        frozenColumns.map { $0.title }
    }

    private var displayRows: [SpreadsheetRow] {
        let base: [SpreadsheetRow]
        if explicitRows.isEmpty {
            base = allRows
        } else {
            let ids = Set(explicitRows.map { $0.id })
            base = allRows.filter { ids.contains($0.id) }
        }

        guard !searchText.isEmpty else { return base }

        let query = searchText.lowercased()
        if !frozenColumns.isEmpty {
            let scopeIndex = min(selectedScope, frozenColumns.count - 1)
            let scopeTitle = frozenColumns[scopeIndex].title
            return base.filter { row in
                row.values.contains { value in
                    value.columnTitle == scopeTitle && value.value.localizedCaseInsensitiveContains(query)
                }
            }
        }
        return base.filter { row in
            row.values.contains { $0.value.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        List(displayRows, id: \.id) { row in
            NavigationLink {
                RowDetailView(sheet: sheet, row: row)
            } label: {
                rowLabel(for: row)
            }
        }
        .navigationTitle(sheet.title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText)
        .searchScopes($selectedScope, scopes: {
            if scopeTitles.count > 1 {
                ForEach(scopeTitles.indices, id: \.self) { index in
                    Text(scopeTitles[index]).tag(index)
                }
            }
        })
        .task {
            do {
                allRows = try await store.fetchRows(for: sheet.title)
            } catch {
                print("SpreadsheetView row load error: \(error)")
            }
        }
    }

    @ViewBuilder
    private func rowLabel(for row: SpreadsheetRow) -> some View {
        HStack(spacing: 12) {
            let imageURLString = row.values.first(where: { $0.imageURL != nil })?.imageURL
            let imageURL = imageURLString.flatMap { URL(string: $0)?.cleaned() }
            RowImage(url: imageURL, fallbackName: row.normalizedName ?? sheet.title)
            VStack(alignment: .leading, spacing: 4) {
                let displayValues = frozenColumns.isEmpty ? [] : frozenColumns.compactMap { col in
                    row.values.first(where: { $0.columnTitle == col.title })
                }
                if let primary = displayValues.first ?? row.values.first {
                    Text(primary.value)
                        .font(.body)
                }
                ForEach(displayValues.dropFirst(), id: \.id) { val in
                    Text("\(val.title): \(val.value)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        SpreadsheetView(sheet: .preview)
    }
    .environment(AppStore.preview)
}
#endif
