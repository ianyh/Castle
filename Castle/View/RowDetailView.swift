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

    /**
     Sheets whose related rows render inline (each as its own section), keyed by the columns through which a match qualifies for inlining. A row in a target sheet only inlines if at least one of its matching columns is in the set — e.g. a Crystal Force Ability inlines when its `Source` matched (viewing the Soul Break it derives from) but NOT when its `Character` matched (viewing the character would otherwise spam every CFA they have). Sheets not in this map fall through to the existing single-link Relationships section. Sheets in this map with no matches via allowed columns are dropped.
     */
    private static let inlineRelationshipColumns: [String: Set<String>] = [
        "Brave": ["Source"],
        "Burst": ["Source"],
        "Crystal Force Abilities": ["Source"],
        "Other": ["Source"],
        "Status": ["Source", "Name"],
        "Synchro": ["Source"],
        "Zenith SB Abilities": ["Source"],
        "Hero Abilities": ["Character"]
    ]

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

            let display = displayedRelationships
            let linkedGroups = display.linked
            let inlinedGroups = display.inlined

            if !linkedGroups.isEmpty {
                Section("Relationships") {
                    ForEach(linkedGroups, id: \.sheetTitle) { group in
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

            ForEach(inlinedGroups, id: \.sheetTitle) { group in
                if let target = navigationTargets[group.sheetTitle] {
                    Section(group.sheetTitle) {
                        ForEach(target.rows, id: \.id) { row in
                            NavigationLink {
                                RowDetailView(sheet: target.sheet, row: row)
                            } label: {
                                inlineRelationshipRow(row)
                            }
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
        let isFrozen = value.isColumnFrozen
        let stackAlignment: HorizontalAlignment = isFrozen ? .center : .leading
        let textAlignment: TextAlignment = isFrozen ? .center : .leading
        let frameAlignment: Alignment = isFrozen ? .center : .leading

        Group {
            if let urlString = value.imageURL, let url = URL(string: urlString) {
                KFImage(url)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 128)
            } else {
                VStack(alignment: stackAlignment, spacing: 4) {
                    Text(value.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(textAlignment)
                    Text(value.value)
                        .font(isFrozen ? .title3 : .body)
                        .multilineTextAlignment(textAlignment)
                }
                .frame(maxWidth: .infinity, alignment: frameAlignment)
            }
        }
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }

    @ViewBuilder
    private func inlineRelationshipRow(_ row: SpreadsheetRow) -> some View {
        HStack(spacing: 12) {
            if let urlString = row.values.first(where: { $0.imageURL != nil })?.imageURL,
               let url = URL(string: urlString)?.cleaned() {
                KFImage(url)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 44, height: 44)
            }
            VStack(alignment: .leading, spacing: 4) {
                if let name = row.normalizedName {
                    Text(name).font(.body)
                }
                if let effect = row.effect {
                    Text(effect)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
        }
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }

    /**
     `"Name"` in an allowlist is a sentinel that matches any column whose title ends in `"Name"` or equals `"Common Name"` — mirroring the name-column convention in `SearchIndex.indexSheet`. Other allowlist entries match the `column_title` literally.
     */
    private static func columnIsAllowed(_ columnTitle: String, allowedColumns: Set<String>) -> Bool {
        if allowedColumns.contains(columnTitle) {
            return true
        }
        if allowedColumns.contains("Name"),
           columnTitle.hasSuffix("Name") || columnTitle == "Common Name" {
            return true
        }
        return false
    }

    /**
     Splits `relationships` into two display buckets, applying per-target column allowlists. A target sheet listed in `inlineRelationshipColumns` is inlined only by the matches whose column is in the allowed set; matches via other columns are dropped (not surfaced as links). Sheets absent from the map stay as the existing single navigation link.
     */
    private var displayedRelationships: (linked: [RelationshipGroup], inlined: [RelationshipGroup]) {
        var linked: [RelationshipGroup] = []
        var inlined: [RelationshipGroup] = []
        for group in relationships {
            if let allowedColumns = Self.inlineRelationshipColumns[group.sheetTitle] {
                let filtered = group.matches.filter {
                    Self.columnIsAllowed($0.columnTitle, allowedColumns: allowedColumns)
                }
                if !filtered.isEmpty {
                    inlined.append(RelationshipGroup(sheetTitle: group.sheetTitle, matches: filtered))
                }
            } else {
                linked.append(group)
            }
        }
        return (linked, inlined)
    }

    private func loadRelationships() async {
        guard let name = row.normalizedName else {
            return
        }
        do {
            relationships = try await store.searchIndex.findRelated(
                rowName: name,
                currentRowID: row.id,
                effect: row.effect
            )
            // Eagerly fetch rows for inline-rendered sections so they appear without
            // a tap-through. Use the post-filter inlined groups so we only fetch the
            // row ids that will actually be rendered.
            for group in displayedRelationships.inlined {
                await loadNavigationTarget(for: group)
            }
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

#if DEBUG
#Preview {
    NavigationStack {
        RowDetailView(sheet: .preview, row: .preview)
    }
    .environment(AppStore.preview)
}
#endif
