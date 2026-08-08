//
//  SSHView.swift
//  GitAgent
//
//  Terminal screen: local macOS shell or saved SSH host → interactive PTY.
//

import SwiftUI

private enum ActiveTerminalKind {
    case ssh
    case local
}

struct SSHView: View {
    @Environment(SSHHostStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(TerminalLaunchCoordinator.self) private var terminalLauncher
    @Environment(\.isWorkspacePage) private var isWorkspacePage

    @State private var session = SSHTerminalSession()
    #if os(macOS)
    @State private var localSession = LocalTerminalSession()
    #endif
    @State private var bridge = TerminalBridge()
    @State private var activeTerminal: ActiveTerminalKind = .ssh
    @State private var activeHost: SSHHostConfig?
    @State private var activeDirectory: String?
    @State private var activeLocalBookmark: Data?
    @State private var editingHost: SSHHostConfig?

    var body: some View {
        Group {
            switch terminalState {
            case .disconnected:
                hostList
            case .connecting, .connected:
                terminalArea
            case .failed(let message):
                failedView(message)
            }
        }
        .navigationTitle(settings.tr(.terminal))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(item: $editingHost) { host in
            SSHHostEditorView(host: host,
                              savedPassword: store.password(for: host),
                              savedPrivateKey: store.privateKey(for: host)) { updated, password, privateKey in
                store.save(updated, password: password, privateKey: privateKey)
            }
        }
        .task(id: terminalLauncher.request?.id) {
            guard let request = terminalLauncher.request else { return }
            switch request.target {
            case .ssh(let hostID):
                if let host = store.hosts.first(where: { $0.id == hostID }) {
                    connect(to: host, directory: request.directory)
                }
            case .local(let bookmarkData):
                #if os(macOS)
                connectLocal(
                    directory: request.directory,
                    bookmarkData: bookmarkData
                )
                #endif
            }
            terminalLauncher.consume(request.id)
        }
        .onChange(of: terminalState) { _, state in
            if state == .connected {
                // The page's initial fit can report its size before the
                // channel is up; that report is dropped and the PTY keeps
                // the default 80x24, so re-fit and re-report on connect.
                bridge.refitAndReportSize()
            }
        }
        .onDisappear { disconnectAll() }
    }

    // MARK: - Host list

    private var hostList: some View {
        Group {
            #if os(macOS)
            List {
                localTerminalRow
                sshHostRows
                Button {
                    editingHost = SSHHostConfig()
                } label: {
                    Label(settings.tr(.addSSHHost), systemImage: "plus")
                }
            }
            #else
            if store.hosts.isEmpty {
                ContentUnavailableView {
                    Label(settings.tr(.noHosts), systemImage: "server.rack")
                } description: {
                    Text(settings.tr(.sshHostsHint))
                }
            } else {
                List {
                    sshHostRows
                }
            }
            #endif
        }
        .macTransparentScrollBackground()
        .toolbar {
            if !isWorkspacePage {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editingHost = SSHHostConfig()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }

    #if os(macOS)
    private var localTerminalRow: some View {
        Button {
            connectLocal(directory: nil, bookmarkData: nil)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "desktopcomputer")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading) {
                    Text(settings.tr(.thisMac))
                    Text(settings.tr(.localShell))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    #endif

    @ViewBuilder
    private var sshHostRows: some View {
        ForEach(store.hosts) { host in
            Group {
                #if os(iOS)
                Button {
                    if host.isConnectable {
                        connect(to: host, directory: nil)
                    }
                } label: {
                    sshHostRowContent(host)
                }
                .buttonStyle(.plain)
                #else
                sshHostRowContent(host)
                    .onTapGesture {
                        if host.isConnectable {
                            connect(to: host, directory: nil)
                        }
                    }
                #endif
            }
            .contextMenu {
                Button {
                    editingHost = host
                } label: {
                    Label(settings.tr(.edit), systemImage: "pencil")
                }
                Button(role: .destructive) {
                    store.delete(host)
                } label: {
                    Label(settings.tr(.delete), systemImage: "trash")
                }
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    store.delete(host)
                } label: {
                    Label(settings.tr(.delete), systemImage: "trash")
                }
                Button {
                    editingHost = host
                } label: {
                    Label(settings.tr(.edit), systemImage: "pencil")
                }
            }
        }
    }

    private func sshHostRowContent(_ host: SSHHostConfig) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "server.rack")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading) {
                Text(host.displayName)
                Text(verbatim: host.connectionDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let jumpHostID = host.jumpHostID,
                   let jumpHost = store.hosts.first(where: { $0.id == jumpHostID }) {
                    Text(L10n.sshVia(host: jumpHost.displayName))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            #if os(macOS)
            Button {
                editingHost = host
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help(settings.tr(.edit))
            #endif
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    // MARK: - Terminal

    private var terminalArea: some View {
        ZStack {
            TerminalView(bridge: bridge, fontSize: settings.terminalFontSize)
            if terminalState == .connecting {
                ProgressView(settings.tr(.connecting))
                    .padding()
                    .background(.regularMaterial, in: .rect(cornerRadius: 12))
            }
        }
        .toolbar {
            if !isWorkspacePage {
                ToolbarItem(placement: .primaryAction) {
                    Button(settings.tr(.disconnect), role: .destructive) {
                        disconnectActive()
                    }
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if isWorkspacePage {
                Button(settings.tr(.disconnect), role: .destructive) {
                    disconnectActive()
                }
                .padding(12)
            }
        }
        .fontSizeShortcuts(9...24,
                           get: { settings.terminalFontSize },
                           set: { settings.terminalFontSize = $0 })
    }

    private func failedView(_ message: String) -> some View {
        ContentUnavailableView {
            Label(settings.tr(.connectionFailed), systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button(settings.tr(.retry)) {
                if activeTerminal == .ssh, let activeHost {
                    connect(to: activeHost, directory: activeDirectory)
                } else {
                    #if os(macOS)
                    connectLocal(
                        directory: activeDirectory,
                        bookmarkData: activeLocalBookmark
                    )
                    #endif
                }
            }
            Button(settings.tr(.back)) { disconnectActive() }
        }
    }

    // MARK: - Connect

    private func connect(to host: SSHHostConfig, directory: String?) {
        #if os(macOS)
        localSession.disconnect()
        #endif
        activeTerminal = .ssh
        activeHost = host
        activeDirectory = directory
        activeLocalBookmark = nil
        session.disconnect()
        bridge.reset()
        session.onOutput = { [weak bridge] data in bridge?.write(data) }
        bridge.onInput = { [weak session] data in session?.send(data) }
        bridge.onResize = { [weak session] cols, rows in session?.resize(cols: cols, rows: rows) }
        var initialInput = Data()
        if let directory {
            initialInput.append(Data("cd \(shellQuote(directory))\n".utf8))
        }
        // zsh displays its inverse-video PROMPT_EOL_MARK (`%`) when the SSH
        // login banner lacks a trailing newline. Ctrl+L clears that transient
        // banner without adding a `clear` command to shell history.
        initialInput.append(0x0C)
        do {
            let route = try store.connectionRoute(for: host)
            session.connect(route: route, initialInput: initialInput)
        } catch {
            session.fail(error.localizedDescription)
        }
    }

    #if os(macOS)
    private func connectLocal(directory: String?, bookmarkData: Data?) {
        session.disconnect()
        activeTerminal = .local
        activeHost = nil
        activeDirectory = directory
        activeLocalBookmark = bookmarkData
        localSession.disconnect()
        bridge.reset()
        localSession.onOutput = { [weak bridge] data in bridge?.write(data) }
        bridge.onInput = { [weak localSession] data in localSession?.send(data) }
        bridge.onResize = { [weak localSession] cols, rows in
            localSession?.resize(cols: cols, rows: rows)
        }
        localSession.connect(directory: directory, bookmarkData: bookmarkData)
        // Start with a clean screen: queue Ctrl+L (clear-screen) so the shell
        // redraws an empty screen with a fresh prompt once it is up.
        localSession.send(Data([0x0C]))
    }
    #endif

    private var terminalState: TerminalSessionState {
        #if os(macOS)
        if activeTerminal == .local {
            return localSession.state
        }
        #endif
        return session.state
    }

    private func disconnectActive() {
        if activeTerminal == .ssh {
            session.disconnect()
        } else {
            #if os(macOS)
            localSession.disconnect()
            #endif
        }
    }

    private func disconnectAll() {
        session.disconnect()
        #if os(macOS)
        localSession.disconnect()
        #endif
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}

// MARK: - Host editor

/// Editor for a display name, an `ssh` command line, and credentials.
struct SSHHostEditorView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SSHHostStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var command: String
    @State private var password: String
    @State private var authenticationKind: SSHAuthenticationKind
    @State private var privateKey: String?
    @State private var jumpHostID: SSHHostConfig.ID?
    private let hostID: UUID
    let onSave: (SSHHostConfig, String?, String?) -> Void

    init(host: SSHHostConfig, savedPassword: String?, savedPrivateKey: String?,
         onSave: @escaping (SSHHostConfig, String?, String?) -> Void) {
        hostID = host.id
        _name = State(initialValue: host.name)
        _command = State(initialValue: host.isConnectable
                         ? host.commandLine : "ssh ")
        _password = State(initialValue: savedPassword ?? "")
        _authenticationKind = State(initialValue: host.jumpHostID == nil
                                    ? host.resolvedAuthenticationKind
                                    : .ed25519Key)
        _privateKey = State(initialValue: savedPrivateKey)
        _jumpHostID = State(initialValue: host.jumpHostID)
        self.onSave = onSave
    }

    private var parsed: SSHHostConfig? {
        var config = SSHHostConfig.parse(command: command)
        config?.id = hostID
        config?.name = name.trimmingCharacters(in: .whitespaces)
        config?.authenticationKind = effectiveAuthenticationKind
        config?.jumpHostID = jumpHostID
        return config
    }

    private var publicKey: String? {
        guard let privateKey else { return nil }
        return try? SSHEd25519Credential.publicKeyLine(from: privateKey)
    }

    private var effectiveAuthenticationKind: SSHAuthenticationKind {
        jumpHostID == nil ? authenticationKind : .ed25519Key
    }

    private var publicKeySetupCommand: String? {
        guard let publicKey else { return nil }
        return """
        mkdir -p ~/.ssh
        chmod 700 ~/.ssh
        grep -qxF '\(publicKey)' ~/.ssh/authorized_keys 2>/dev/null || printf '%s\\n' '\(publicKey)' >> ~/.ssh/authorized_keys
        chmod 600 ~/.ssh/authorized_keys
        """
    }

    private var canSave: Bool {
        guard parsed != nil else { return false }
        switch effectiveAuthenticationKind {
        case .password: return !password.isEmpty
        case .ed25519Key: return publicKey != nil
        }
    }

    /// Only complain about an unparseable command once the user typed one.
    private var showsParseError: Bool {
        parsed == nil && command.trimmingCharacters(in: .whitespaces) != "ssh"
    }

    var body: some View {
        ScrollView {
          VStack(alignment: .leading, spacing: 16) {
            Text(settings.tr(.sshHostEditorTitle))
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text(settings.tr(.sshName))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                TextField(settings.tr(.sshName), text: $name)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    // Not a login/contact form — an empty content type keeps
                    // iOS AutoFill heuristics out (`.none` would mean nil).
                    .textContentType(UITextContentType(rawValue: ""))
                    .autocorrectionDisabled()
                    #endif
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(settings.tr(.sshCommand))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    TextField("ssh user@host [-p port]", text: $command)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textContentType(UITextContentType(rawValue: ""))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #endif
                    Button {
                        if let text = pasteFromClipboard() { command = text }
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                }
                if showsParseError {
                    Text(settings.tr(.sshCommandInvalid))
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if let parsed {
                    Text(verbatim: parsed.connectionDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(settings.tr(.sshAuthentication))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if jumpHostID == nil {
                    Picker(settings.tr(.sshAuthentication), selection: $authenticationKind) {
                        Text(settings.tr(.sshPasswordAuthentication))
                            .tag(SSHAuthenticationKind.password)
                        Text(settings.tr(.sshKeyAuthentication))
                            .tag(SSHAuthenticationKind.ed25519Key)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                } else {
                    Text(settings.tr(.sshKeyAuthentication))
                    Text(settings.tr(.sshJumpRequiresKey))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if effectiveAuthenticationKind == .password {
                VStack(alignment: .leading, spacing: 6) {
                    Text(settings.tr(.sshPassword))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        SecureField(settings.tr(.sshPassword), text: $password)
                            .textFieldStyle(.roundedBorder)
                            #if os(iOS)
                            // Keep the value obscured while avoiding login-form
                            // AutoFill heuristics for this host editor.
                            .textContentType(UITextContentType(rawValue: ""))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            #endif
                        Button {
                            if let text = pasteFromClipboard() { password = text }
                        } label: {
                            Image(systemName: "doc.on.clipboard")
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(settings.tr(.sshPublicKey))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if let publicKey {
                        Text(verbatim: publicKey)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(4)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Button(settings.tr(.copyPublicKey)) {
                                    copyToClipboard(publicKey)
                                }
                                if let publicKeySetupCommand {
                                    Button(settings.tr(.copySSHSetupCommand)) {
                                        copyToClipboard(publicKeySetupCommand)
                                    }
                                }
                            }
                            Button(settings.tr(.generateNewKey), role: .destructive) {
                                privateKey = SSHEd25519Credential.generatePrivateKey()
                            }
                        }
                    } else {
                        Button(settings.tr(.generateSSHKey)) {
                            privateKey = SSHEd25519Credential.generatePrivateKey()
                        }
                    }
                    Text(settings.tr(.sshPublicKeyHint))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(settings.tr(.sshJumpHost))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Picker(settings.tr(.sshJumpHost), selection: $jumpHostID) {
                    Text(settings.tr(.sshDirectConnection))
                        .tag(Optional<SSHHostConfig.ID>.none)
                    ForEach(store.availableJumpHosts(for: hostID)) { jumpHost in
                        Text(jumpHost.displayName)
                            .tag(Optional(jumpHost.id))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                Text(settings.tr(.sshJumpHostHint))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button(settings.tr(.cancel)) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(settings.tr(.save)) {
                    if let parsed {
                        onSave(
                            parsed,
                            password.isEmpty ? nil : password,
                            privateKey
                        )
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
          }
          .padding(20)
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 560)
        #endif
        .onChange(of: jumpHostID) { _, newValue in
            if newValue != nil {
                authenticationKind = .ed25519Key
            }
        }
    }
}
