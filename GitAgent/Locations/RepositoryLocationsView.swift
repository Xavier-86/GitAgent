//
//  RepositoryLocationsView.swift
//  GitAgent
//
//  Manages the computers and working-tree paths attached to one GitHub repository.
//

import SwiftUI

struct RepositoryLocationsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(GitHubAuthManager.self) private var auth
    @Environment(RepositoryLocationStore.self) private var locations
    @Environment(SSHHostStore.self) private var hosts
    @Environment(TerminalLaunchCoordinator.self) private var terminalLauncher
    @Environment(\.dismiss) private var dismiss

    let repo: Repo

    @State private var isAdding = false
    @State private var isDeploying = false
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
        repositoryLayout
            .sheet(isPresented: $isAdding) {
                AddRepositoryLocationView { hostID, path, bookmarkData in
                    if let hostID {
                        let id = locations.add(repository: repo, hostID: hostID, path: path)
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
                            Task { await verify(id) }
                        }
                    #endif
                }
            }
            .sheet(isPresented: $isDeploying) {
                RepoLaunchForm(repo: repo)
            }
            .onChange(of: terminalLauncher.request?.id) { _, requestID in
                if requestID != nil { dismiss() }
            }
            .task {
                guard !didAutoVerify else { return }
                didAutoVerify = true
                for location in repositoryLocations {
                    await verify(location.id)
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
        NavigationStack {
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
                            isDeploying = true
                        } label: {
                            Label(settings.tr(.deployRepository), systemImage: "shippingbox.and.arrow.backward")
                        }
                        Button {
                            isAdding = true
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
                    isAdding = true
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(!canAddLocation)
                .help(settings.tr(.linkExistingRepository))

                Spacer()

                Button {
                    isDeploying = true
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
                                systemName: location.isConnected
                                    ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                            )
                            .foregroundStyle(location.isConnected ? .green : .red)
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
                        } else if location.isConnected {
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
        }
        .padding(.vertical, 4)
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
        locations.markChecking(id)
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
                guard let password = hosts.password(for: host), !password.isEmpty else {
                    locations.markFailed(id, error: settings.tr(.sshPasswordMissing))
                    return
                }
                probe = try await RepositoryLocationVerifier.verify(
                    host: host,
                    password: password,
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
        } catch let error as RepositoryLocationVerifier.VerificationError {
            locations.markFailed(id, error: error.message(expectedRepository: repo.fullName))
        } catch {
            locations.markFailed(
                id,
                error: "\(settings.tr(.connectionFailed)): \(error.localizedDescription)"
            )
        }
    }
}
