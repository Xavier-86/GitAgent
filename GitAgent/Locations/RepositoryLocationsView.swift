//
//  RepositoryLocationsView.swift
//  GitAgent
//
//  Manages the computers and working-tree paths attached to one GitHub repository.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

struct RepositoryLocationsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(GitHubAuthManager.self) private var auth
    @Environment(RepositoryLocationStore.self) private var locations
    @Environment(SSHHostStore.self) private var hosts
    @Environment(TerminalLaunchCoordinator.self) private var terminalLauncher
    @Environment(\.dismiss) private var dismiss

    let repo: Repo

    @State private var isAdding = false
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
        NavigationStack {
            Group {
                if repositoryLocations.isEmpty {
                    ContentUnavailableView {
                        Label(settings.tr(.noRepositoryLocations), systemImage: "externaldrive.badge.questionmark")
                    } description: {
                        Text(settings.tr(.repositoryLocationsHint))
                    } actions: {
                        Button(settings.tr(.addRepositoryLocation)) {
                            isAdding = true
                        }
                        .disabled(!canAddLocation)
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
            .navigationTitle(settings.tr(.repositoryLocations))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(macOS)
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        isAdding = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(!canAddLocation)
                    .tint(.gray)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(settings.tr(.done)) { dismiss() }
                        .tint(.gray)
                }
                #else
                ToolbarItem(placement: .cancellationAction) {
                    Button(settings.tr(.done)) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isAdding = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(!canAddLocation)
                }
                #endif
            }
            #if os(iOS)
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
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 420)
        #endif
        .sheet(isPresented: $isAdding) {
            AddRepositoryLocationView(repo: repo) { hostID, path, bookmarkData in
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
        .task {
            guard !didAutoVerify else { return }
            didAutoVerify = true
            for location in repositoryLocations {
                await verify(location.id)
            }
        }
    }

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
                            Image(systemName: location.isConnected
                                  ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                .foregroundStyle(location.isConnected ? .green : .red)
                        }
                    }
                    .frame(width: 20, height: 20)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(location.isLocal
                             ? settings.tr(.thisMac)
                             : host?.locationDisplayName ?? settings.tr(.computerUnavailable))
                            .font(.headline)
                        Text(location.path)
                            .font(.callout.monospaced())
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
        guard location.isConnected else { return }

        let hostID: SSHHostConfig.ID
        if let configuredHostID = location.hostID {
            hostID = configuredHostID
        } else {
            terminalLauncher.openLocal(
                directory: location.path,
                bookmarkData: location.bookmarkData
            )
            dismiss()
            return
        }

        terminalLauncher.open(hostID: hostID, directory: location.path)
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

private enum RepositoryComputerChoice: Hashable {
    case local
    case remote(SSHHostConfig.ID)
}

private struct AddRepositoryLocationView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SSHHostStore.self) private var hosts
    @Environment(\.dismiss) private var dismiss

    let repo: Repo
    let onSave: (SSHHostConfig.ID?, String, Data?) -> Void

    #if os(macOS)
    @State private var selectedComputer: RepositoryComputerChoice? = .local
    @State private var bookmarkData: Data?
    @State private var selectionError: String?
    #else
    @State private var selectedComputer: RepositoryComputerChoice?
    #endif
    @State private var path = ""

    private var trimmedPath: String {
        path.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        guard let selectedComputer, !trimmedPath.isEmpty else { return false }
        #if os(macOS)
        if selectedComputer == .local {
            return bookmarkData != nil
        }
        #endif
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(settings.tr(.computer)) {
                    Picker(settings.tr(.computer), selection: $selectedComputer) {
                        Text(settings.tr(.selectComputer))
                            .tag(Optional<RepositoryComputerChoice>.none)
                        #if os(macOS)
                        Text(settings.tr(.thisMac))
                            .tag(Optional(RepositoryComputerChoice.local))
                        #endif
                        ForEach(hosts.hosts) { host in
                            Text(host.locationDisplayName)
                                .tag(Optional(RepositoryComputerChoice.remote(host.id)))
                        }
                    }
                    .onChange(of: selectedComputer) {
                        #if os(macOS)
                        if selectedComputer != .local {
                            bookmarkData = nil
                            selectionError = nil
                            path = ""
                        }
                        #endif
                    }
                }

                Section {
                    #if os(macOS)
                    if selectedComputer == .local {
                        HStack {
                            TextField(settings.tr(.repositoryPathHint), text: $path)
                                .disabled(true)
                            Button(settings.tr(.chooseFolder)) {
                                Task { await chooseLocalFolder() }
                            }
                        }
                        if let selectionError {
                            Text(selectionError)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        TextField(settings.tr(.repositoryPathHint), text: $path)
                    }
                    #else
                    TextField(settings.tr(.repositoryPathHint), text: $path)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #endif
                    #endif
                } header: {
                    Text(settings.tr(.repositoryPath))
                } footer: {
                    #if os(macOS)
                    Text(settings.tr(selectedComputer == .local
                                     ? .localRepositoryPathFooter
                                     : .repositoryPathFooter))
                        .fixedSize(horizontal: false, vertical: true)
                    #else
                    Text(settings.tr(.repositoryPathFooter))
                    #endif
                }
            }
            .navigationTitle(settings.tr(.addRepositoryLocation))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(settings.tr(.cancel)) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(settings.tr(.saveAndVerify)) {
                        guard let selectedComputer else { return }
                        switch selectedComputer {
                        case .local:
                            #if os(macOS)
                            guard let bookmarkData else { return }
                            onSave(nil, trimmedPath, bookmarkData)
                            dismiss()
                            #endif
                        case .remote(let hostID):
                            onSave(hostID, trimmedPath, nil)
                            dismiss()
                        }
                    }
                    .disabled(!canSave)
                }
            }
        }
        #if os(macOS)
        // Fixed width so the Form lays out within the sheet instead of
        // overflowing past its edges; height stays flexible for the error line.
        .frame(width: 560)
        .frame(minHeight: 280)
        #endif
    }

    #if os(macOS)
    @MainActor
    private func chooseLocalFolder() async {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = settings.tr(.chooseFolder)

        guard await panel.begin() == .OK, let directoryURL = panel.url else { return }
        do {
            bookmarkData = try directoryURL.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            path = directoryURL.path
            selectionError = nil
        } catch {
            bookmarkData = nil
            selectionError = "\(settings.tr(.folderSelectionFailed)): \(error.localizedDescription)"
        }
    }
    #endif
}
