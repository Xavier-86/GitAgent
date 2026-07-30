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
                              savedPassword: store.password(for: host)) { updated, password in
                store.save(updated, password: password)
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
        .onDisappear { disconnectAll() }
    }

    // MARK: - Host list

    private var hostList: some View {
        Group {
            #if os(macOS)
            List {
                localTerminalRow
                sshHostRows
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editingHost = SSHHostConfig()
                } label: {
                    Image(systemName: "plus")
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
            ToolbarItem(placement: .primaryAction) {
                Button(settings.tr(.disconnect), role: .destructive) {
                    disconnectActive()
                }
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
        guard let password = store.password(for: host), !password.isEmpty else {
            // No password saved yet — open the editor to collect it first.
            editingHost = host
            return
        }
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
        let initialInput = directory.map {
            Data("cd \(shellQuote($0))\n".utf8)
        }
        session.connect(host: host, password: password, initialInput: initialInput)
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

/// Editor for a display name, an `ssh` command line, and a password.
struct SSHHostEditorView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var command: String
    @State private var password: String
    private let hostID: UUID
    let onSave: (SSHHostConfig, String?) -> Void

    init(host: SSHHostConfig, savedPassword: String?,
         onSave: @escaping (SSHHostConfig, String?) -> Void) {
        hostID = host.id
        _name = State(initialValue: host.name)
        _command = State(initialValue: host.isConnectable
                         ? host.commandLine : "ssh ")
        _password = State(initialValue: savedPassword ?? "")
        self.onSave = onSave
    }

    private var parsed: SSHHostConfig? {
        var config = SSHHostConfig.parse(command: command)
        config?.id = hostID
        config?.name = name.trimmingCharacters(in: .whitespaces)
        return config
    }

    /// Only complain about an unparseable command once the user typed one.
    private var showsParseError: Bool {
        parsed == nil && command.trimmingCharacters(in: .whitespaces) != "ssh"
    }

    var body: some View {
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
                Text(settings.tr(.sshPassword))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    // A plain field on purpose: pasteable, and it stops iOS
                    // from treating this sheet as a Password AutoFill form.
                    TextField(settings.tr(.sshPassword), text: $password)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
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

            HStack {
                Spacer()
                Button(settings.tr(.cancel)) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(settings.tr(.save)) {
                    if let parsed {
                        onSave(parsed, password.isEmpty ? nil : password)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(parsed == nil || password.isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 400)
        #if os(macOS)
        .fixedSize()
        #endif
    }
}
