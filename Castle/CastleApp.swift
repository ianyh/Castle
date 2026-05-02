//
//  CastleApp.swift
//  Castle
//
//  Created by Ian Ynda-Hummel on 9/19/17.
//  Copyright © 2017 Ian Ynda-Hummel. All rights reserved.
//

import Kingfisher
import SwiftUI

@main
struct CastleApp: App {
    init() {
        ImageCache.default.diskStorage.config.expiration = .never
        ImageCache.default.diskStorage.config.sizeLimit = 0
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

private struct RootView: View {
    @State private var store: AppStore?
    @State private var initError: Error?

    var body: some View {
        Group {
            if let store {
                MainTabs()
                    .environment(store)
            } else {
                ProgressView()
            }
        }
        .alert(
            "Couldn't open the database.",
            isPresented: Binding(get: { initError != nil }, set: { if !$0 { initError = nil } }),
            presenting: initError
        ) { _ in
            Button("Retry") {
                Task { await initialize() }
            }
        } message: { error in
            Text(error.localizedDescription)
        }
        .task {
            guard store == nil, initError == nil else {
                return
            }
            await initialize()
        }
    }

    private func initialize() async {
        do {
            let db = try AppStore.makeDatabase()
            store = AppStore(db: db)
        } catch {
            initError = error
        }
    }
}

private struct MainTabs: View {
    @Environment(AppStore.self) private var store
    @State private var showFirstSyncAlert = false
    @State private var stateLoaded = false

    var body: some View {
        TabView {
            NavigationStack {
                SpreadsheetListView()
            }
            .tabItem {
                Label("Archive", image: "categories")
            }

            NavigationStack {
                SpecialsView()
            }
            .tabItem {
                Label("Featured", systemImage: "star.fill")
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", image: "settings")
            }
        }
        .alert(
            "Welcome",
            isPresented: $showFirstSyncAlert
        ) {
            Button("Sync") {
                Task { await store.sync() }
            }
        } message: {
            Text("Looks like this is your first time in the app. We need to sync the database to get you started.")
        }
        .task {
            await store.loadState()
            stateLoaded = true
            if store.lastUpdate == nil {
                showFirstSyncAlert = true
            }
        }
    }
}
