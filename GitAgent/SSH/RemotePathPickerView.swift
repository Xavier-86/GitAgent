//
//  RemotePathPickerView.swift
//  GitAgent
//
//  Step-by-step directory browser for choosing a path on an SSH host.
//

import SwiftUI

/// Identifiable SSH route for moving from a path-entry form into the browser.
struct RemoteBrowseContext: Identifiable {
    let route: SSHConnectionRoute

    var id: SSHHostConfig.ID { route.target.id }
}

struct RemotePathPickerView: View {
    @Environment(AppSettings.self) private var settings

    let route: SSHConnectionRoute
    /// Where browsing starts; an empty value starts at the home directory.
    let initialPath: String
    let onBack: () -> Void
    let onSelect: (String) -> Void

    @State private var requestedPath = ""
    @State private var resolvedPath = ""
    @State private var directories: [String] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView(settings.tr(.loading))
            } else if let errorMessage {
                ContentUnavailableView {
                    Label(settings.tr(.loadFailed), systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button(settings.tr(.retry)) {
                        Task { await load(path: requestedPath) }
                    }
                }
            } else {
                List {
                    if resolvedPath != "/" {
                        Button {
                            Task { await load(path: parentPath) }
                        } label: {
                            Label("..", systemImage: "arrow.up")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                    }
                    ForEach(directories, id: \.self) { name in
                        Button {
                            Task { await load(path: childPath(name)) }
                        } label: {
                            Label(name, systemImage: "folder")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                    }
                }
                .overlay {
                    if directories.isEmpty {
                        Text(settings.tr(.emptyFolder))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(resolvedPath.isEmpty ? settings.tr(.browse) : resolvedPath)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(settings.tr(.back), action: onBack)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(settings.tr(.selectThisFolder)) {
                    onSelect(resolvedPath)
                }
                .disabled(isLoading || errorMessage != nil || resolvedPath.isEmpty)
            }
        }
        #if os(macOS)
            .frame(minWidth: 420, minHeight: 360)
        #endif
        .task {
            let start = initialPath.trimmingCharacters(in: .whitespacesAndNewlines)
            await load(path: start.isEmpty ? "~" : start)
        }
    }

    private var parentPath: String {
        (resolvedPath as NSString).deletingLastPathComponent
    }

    private func childPath(_ name: String) -> String {
        resolvedPath == "/" ? "/\(name)" : "\(resolvedPath)/\(name)"
    }

    @MainActor
    private func load(path: String) async {
        requestedPath = path
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result = try await SSHConnection.retryingTransientFailure {
                try await RemoteDirectoryBrowser.listDirectories(
                    route: route,
                    path: path
                )
            }
            resolvedPath = result.path
            directories = result.directories
        } catch let error as RemoteDirectoryBrowser.BrowseError {
            switch error {
            case .pathMissing:
                errorMessage = settings.tr(.repositoryPathMissing)
            case .listingFailed:
                errorMessage = settings.tr(.directoryListingFailed)
            }
        } catch {
            errorMessage = "\(settings.tr(.connectionFailed)): \(error.localizedDescription)"
        }
    }
}
