//
//  RowDetailView.swift
//
//  Created by Ian Ynda-Hummel on 9/23/17.
//  Copyright © 2017 Ian Ynda-Hummel. All rights reserved.
//

import Kingfisher
import SwiftUI

struct RowDetailView: View {
    let sheet: Spreadsheet
    let row: SpreadsheetRow

    @Environment(AppStore.self) private var store

    @State private var relationships: [RelationshipGroup] = []
    @State private var navigationTargets: [String: (sheet: Spreadsheet, rows: [SpreadsheetRow])] = [:]

    private var frozenValues: [RowValue] {
        row.values.filter { $0.isColumnFrozen }.sorted { $0.id < $1.id }
    }

    private var normalValues: [RowValue] {
        row.values.filter { !$0.isColumnFrozen }.sorted { $0.id < $1.id }
    }

    var body: some View {
        List {
            Section {
                ForEach(frozenValues, id: \.id) { value in
                    rowValueRow(value)
                }
            }

            if !relationships.isEmpty {
                Section("Relationships") {
                    ForEach(relationships, id: \.sheetTitle) { group in
                        NavigationLink(group.sheetTitle) {
                            if let target = navigationTargets[group.sheetTitle] {
                                SpreadsheetView(sheet: target.sheet, explicitRows: target.rows)
                            }
                        }
                        .task(id: group.sheetTitle) {
                            await loadNavigationTarget(for: group)
                        }
                    }
                }
            }

            Section {
                ForEach(normalValues, id: \.id) { value in
                    rowValueRow(value)
                }
            }
        }
        .listStyle(.grouped)
        .navigationTitle(row.normalizedName ?? sheet.title)
        .task {
            await loadRelationships()
        }
    }

    @ViewBuilder
    private func rowValueRow(_ value: RowValue) -> some View {
        if let urlString = value.imageURL, let url = URL(string: urlString) {
            KFImage(url)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 128)
        } else {
            HStack {
                Text(value.title)
                    .font(value.isColumnFrozen ? .headline : .body)
                    .foregroundStyle(value.isColumnFrozen ? .primary : .secondary)
                Spacer()
                Text(value.value)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    private func loadRelationships() async {
        guard let name = row.normalizedName else {
            return
        }
        do {
            relationships = try await store.searchIndex.findRelated(
                rowName: name,
                sheetNormalizedName: sheet.normalizedName,
                effect: row.effect
            )
        } catch {
            print("Relationship load error: \(error)")
        }
    }

    private func loadNavigationTarget(for group: RelationshipGroup) async {
        let sheetTitle = group.sheetTitle
        guard navigationTargets[sheetTitle] == nil else {
            return
        }
        do {
            guard let targetSheet = try await store.fetchSpreadsheet(title: sheetTitle) else {
                return
            }
            let rows = try await store.fetchRows(ids: group.rowIDs)
            navigationTargets[sheetTitle] = (sheet: targetSheet, rows: rows)
        } catch {
            print("Navigation target load error: \(error)")
        }
    }
}

struct LazyRowDetailLoader: View {
    let rowID: String
    let sheetTitle: String

    @Environment(AppStore.self) private var store
    @State private var target: (sheet: Spreadsheet, row: SpreadsheetRow)?

    var body: some View {
        Group {
            if let target {
                RowDetailView(sheet: target.sheet, row: target.row)
            } else {
                ProgressView()
            }
        }
        .task {
            await loadTarget()
        }
    }

    private func loadTarget() async {
        do {
            guard
                let row = try await store.fetchRows(ids: [rowID]).first,
                let sheet = try await store.fetchSpreadsheet(title: sheetTitle)
            else {
                return
            }
            target = (sheet: sheet, row: row)
        } catch {
            print("LazyRowDetailLoader error: \(error)")
        }
    }
}
