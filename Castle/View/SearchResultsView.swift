//
//  SearchResultsView.swift
//
//  Created by Ian Ynda-Hummel on 1/8/19.
//  Copyright © 2019 Ian Ynda-Hummel. All rights reserved.
//

import Kingfisher
import SwiftUI

struct SearchResultsView: View {
    let results: [SearchResult]
    let title: String

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
        .navigationTitle(title)
    }
}
