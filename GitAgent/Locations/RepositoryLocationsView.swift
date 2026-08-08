//
//  RepositoryLocationsView.swift
//  GitAgent
//
//  Manages the computers and working-tree paths attached to one GitHub repository.
//

import SwiftUI

struct RepositoryLocationsView: View {
    private enum Destination: Hashable {
        case addLocation
        case deploy
    }

    @Environment(AppSettings.self) private var settings
    @Environment(GitHubAuthManager.self) private var auth
    @Environment(RepositoryLocationStore.self) private var locations
    @Environment(SSHHostStore.self) private var hosts
    @Environment(TerminalLaunchCoordinator.self) private var terminalLauncher
    @Environment(WorkspaceStore.self) private var workspace
    @Environment(\.dismiss) private var dismiss

    let repo: Repo

    @State private var navigationPath: [Destination] = []
    @State private var verifyingIDs: Set<UUID> = []
    @State private var didAutoVerify = false

    private var repositoryLocations: [RepositoryLocation] {
        locations.locations(for: repo.id)
    }

    private var canAddLocation: Bool {
        #if os(macOS)
            true
        #else
            !hosts.hosts.isEmpty
        #endif
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            repositoryLayout
                .navigationDestination(for: Destination.self) { destination in
                    switch destination {
                    case .addLocation:
                        AddRepositoryLocationView(
                            onBack: popDestination,
                            onSave: saveLocation
                        )
                    case .deploy:
                        RepoLaunchForm(repo: repo, presentation: .navigation)
                    }
                }
        }
        .onChange(of: terminalLauncher.request?.id) { _, requestID in
            if requestID != nil { dismiss() }
        }
        .task {
            guard !didAutoVerify else { return }
            didAutoVerify = true
            let locationIDs = repositoryLocations.map(\.id)
            await withTaskGroup(of: Void.self) { group in
                for id in locationIDs {
                    group.addTask { await verify(id) }
                }
            }
        }
    }

    @ViewBuilder
    private var repositoryLayout: some View {
        #if os(macOS)
            VStack(spacing: 0) {
                repositoryHeader
                Divider()
                repositoryContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                repositoryActions
            }
            .frame(
                minWidth: 520,
                idealWidth: 720,
                maxWidth: .infinity,
                minHeight: 420,
                idealHeight: 520,
                maxHeight: .infinity
            )
        #else
        repositoryContent
            .navigationTitle(settings.tr(.repositoryLocations))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(settings.tr(.done)) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            navigationPath.append(.deploy)
                        } label: {
                            Label(settings.tr(.deployRepository), systemImage: "shippingbox.and.arrow.backward")
                        }
                        Button {
                            navigationPath.append(.addLocation)
                        } label: {
                            Label(settings.tr(.linkExistingRepository), systemImage: "link")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(!canAddLocation)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if hosts.hosts.isEmpty {
                    Label(settings.tr(.addSSHHostFirst), systemImage: "server.rack")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(.bar)
                }
            }
        #endif
    }

    @ViewBuilder
    private var repositoryContent: some View {
        if repositoryLocations.isEmpty {
            ContentUnavailableView {
                Label(
                    settings.tr(.noRepositoryLocations), systemImage: "externaldrive.badge.questionmark")
            } description: {
                Text(settings.tr(.repositoryLocationsHint))
            }
        } else {
            List {
                ForEach(repositoryLocations) { location in
                    locationRow(location)
                        .contextMenu {
                            Button {
                                Task { await verify(location.id) }
                            } label: {
                                Label(settings.tr(.verify), systemImage: "arrow.clockwise")
                            }
                            Button(role: .destructive) {
                                locations.delete(location.id)
                            } label: {
                                Label(settings.tr(.delete), systemImage: "trash")
                            }
                        }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        locations.delete(repositoryLocations[index].id)
                    }
                }
            }
        }
    }

    #if os(macOS)
        private var repositoryHeader: some View {
            HStack {
                Text(settings.tr(.repositoryLocations))
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(.bar)
        }

        private var repositoryActions: some View {
            HStack(spacing: 10) {
                Button {
                    navigationPath.append(.addLocation)
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(!canAddLocation)
                .help(settings.tr(.linkExistingRepository))

                Spacer()

                Button {
                    navigationPath.append(.deploy)
                } label: {
                    Label(
                        settings.tr(.deployRepository),
                        systemImage: "shippingbox.and.arrow.backward"
                    )
                }
                .disabled(!canAddLocation)
                .help(settings.tr(.deployRepository))

                Button(settings.tr(.done)) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .buttonStyle(.bordered)
            .tint(.gray)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
        }
    #endif

    private func locationRow(_ location: RepositoryLocation) -> some View {
        let isVerifying = verifyingIDs.contains(location.id)
        let wasConnected = location.lastConnectionWasSuccessful
        let host = location.hostID.flatMap { hostID in
            hosts.hosts.first { $0.id == hostID }
        }

        return HStack(alignment: .top, spacing: 12) {
            Button {
                openInTerminal(location)
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Group {
                        if isVerifying {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(
                                systemName: wasConnected
                                    ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                            )
                            .foregroundStyle(wasConnected ? .green : .red)
                        }
                    }
                    .frame(width: 20, height: 20)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(
                            location.isLocal
                                ? settings.tr(.thisMac)
                                : host?.locationDisplayName ?? settings.tr(.computerUnavailable)
                        )
                        .font(.headline)
                        Text(location.path)
                            .font(.callout.monospaced())
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        if isVerifying {
                            Text(settings.tr(.verifying))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if wasConnected {
                            Text(settings.tr(.connected))
                                .font(.caption)
                                .foregroundStyle(.green)
                        } else if let error = location.lastError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        } else {
                            Text(settings.tr(.notConnected))
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }

                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!location.isConnected || (!location.isLocal && host == nil))

            Button {
                Task { await verify(location.id) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(isVerifying)
            .help(settings.tr(.verify))

            if location.isLocal {
                #if os(macOS)
                    Button {
                        openLocalRepository(location)
                    } label: {
                        Label(settings.tr(.view), systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!location.isConnected)
                    .help(settings.tr(.viewLocalRepository))
                #endif
            } else if let host {
                Button {
                    openRemoteRepository(location, host: host)
                } label: {
                    Label(settings.tr(.view), systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .disabled(!location.isConnected)
                .help(settings.tr(.viewRemoteRepository))
            }
        }
        .padding(.vertical, 4)
    }

    private func popDestination() {
        guard !navigationPath.isEmpty else { return }
        navigationPath.removeLast()
    }

    private func saveLocation(hostID: SSHHostConfig.ID?, path: String, bookmarkData: Data?) {
        if let hostID {
            let id = locations.add(repository: repo, hostID: hostID, path: path)
            popDestination()
            Task { await verify(id) }
            return
        }
        #if os(macOS)
            if let bookmarkData {
                let id = locations.addLocal(
                    repository: repo,
                    path: path,
                    bookmarkData: bookmarkData
                )
                popDestination()
                Task { await verify(id) }
            }
        #endif
    }

    #if os(macOS)
        private func openLocalRepository(_ location: RepositoryLocation) {
            guard location.isLocal, location.isConnected else { return }
            workspace.showLocalRepository(repo, location: location)
            dismiss()
        }
    #endif

    private func openRemoteRepository(
        _ location: RepositoryLocation,
        host: SSHHostConfig
    ) {
        guard !location.isLocal, location.isConnected else { return }
        workspace.showRemoteRepository(repo, location: location, host: host)
        dismiss()
    }

    private func openInTerminal(_ location: RepositoryLocation) {
        guard terminalLauncher.open(location) else { return }
        dismiss()
    }

    @MainActor
    private func verify(_ id: RepositoryLocation.ID) async {
        guard !verifyingIDs.contains(id),
            let location = locations.location(id: id)
        else { return }

        verifyingIDs.insert(id)
        defer { verifyingIDs.remove(id) }

        do {
            let probe: RepositoryLocationProbe
            if location.isLocal {
                #if os(macOS)
                    guard let bookmarkData = location.bookmarkData else {
                        throw RepositoryLocationVerifier.VerificationError.localAccessDenied
                    }
                    probe = try RepositoryLocationVerifier.verifyLocal(
                        bookmarkData: bookmarkData,
                        expectedRepository: repo.fullName
                    )
                #else
                    locations.markFailed(id, error: settings.tr(.computerUnavailable))
                    return
                #endif
            } else {
                guard let hostID = location.hostID,
                    let host = hosts.hosts.first(where: { $0.id == hostID })
                else {
                    locations.markFailed(id, error: settings.tr(.computerUnavailable))
                    return
                }
                probe = try await RepositoryLocationVerifier.verify(
                    route: try hosts.connectionRoute(for: host),
                    path: location.path,
                    expectedRepository: repo.fullName
                )
            }

            guard let client = auth.client else {
                throw GitHubError.unauthorized
            }
            let onlineRepository = try await client.verifyRepoConnection(
                owner: repo.owner.login,
                name: repo.name
            )
            guard onlineRepository.id == repo.id else {
                throw RepositoryLocationVerifier.VerificationError.repositoryMismatch(
                    found: [onlineRepository.fullName]
                )
            }

            locations.markConnected(
                id,
                canonicalPath: probe.canonicalPath,
                remoteName: probe.remoteName,
                bookmarkData: probe.bookmarkData
            )
        } catch is CancellationError {
            return
        } catch let error as RepositoryLocationVerifier.VerificationError {
            let message = error.message(expectedRepository: repo.fullName)
            switch error {
            case .remoteUnreachable:
                locations.markTemporarilyUnavailable(id, error: message)
            default:
                locations.markFailed(id, error: message)
            }
        } catch {
            guard !Task.isCancelled else { return }
            locations.markTemporarilyUnavailable(
                id,
                error: "\(settings.tr(.connectionFailed)): \(error.localizedDescription)"
            )
        }
    }
}
