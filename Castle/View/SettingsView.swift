//
//  SettingsView.swift
//
//  Created by Ian Ynda-Hummel on 9/24/17.
//  Copyright © 2017 Ian Ynda-Hummel. All rights reserved.
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppStore.self) private var store

    @State private var showSyncConfirm = false
    @State private var showImageConfirm = false
    @State private var imageLoadProgress: String? = nil
    @State private var syncError: Error? = nil
    @State private var imageTask: Task<Void, Never>? = nil

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        Form {
            Section {
                LabeledContent("Last update") {
                    if let date = store.lastUpdate {
                        Text(Self.dateFormatter.string(from: date))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Never")
                            .foregroundStyle(.secondary)
                    }
                }

                Button(store.isSyncing ? "Syncing…" : "Sync") {
                    showSyncConfirm = true
                }
                .disabled(store.isSyncing)

                Link("Go to archive", destination: URL(string: "https://docs.google.com/spreadsheets/d/1f8OJIQhpycljDQ8QNDk_va1GJ1u7RVoMaNjFcHH0LKk/")!)
            } header: {
                Text("Archive Data")
            } footer: {
                Text("Credit to the FFRK Community Database and its maintainers.")
            }

            Section("Images") {
                Button(imageLoadProgress != nil ? "Downloading…" : "Download images") {
                    showImageConfirm = true
                }
                .disabled(imageLoadProgress != nil)

                if let progress = imageLoadProgress {
                    LabeledContent("Progress", value: progress)
                }

                Button("Clear image cache", role: .destructive) {
                    store.clearImageCache()
                }
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog(
            "This may take a while.",
            isPresented: $showSyncConfirm,
            titleVisibility: .visible
        ) {
            Button("Sync", role: .destructive) {
                Task { await store.sync() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "This may take a while.",
            isPresented: $showImageConfirm,
            titleVisibility: .visible
        ) {
            Button("Download", role: .destructive) {
                startImageDownload()
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Error", isPresented: .constant(syncError != nil)) {
            Button("OK") { syncError = nil }
        } message: {
            Text(syncError?.localizedDescription ?? "")
        }
    }

    private func startImageDownload() {
        imageTask?.cancel()
        imageTask = Task {
            do {
                for try await progress in store.preloadImages() {
                    imageLoadProgress = progress
                }
            } catch {
                syncError = error
            }
            imageLoadProgress = nil
        }
    }
}
