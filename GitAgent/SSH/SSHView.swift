//
//  SSHView.swift
//  GitAgent
//
//  SSH screen: saved hosts → connect → interactive remote terminal.
//

import SwiftUI

struct SSHView: View {
    @Environment(SSHHostStore.self) private var store
    @Environment(AppSettings.self) private var settings

    @State private var session = SSHTerminalSession()
    @State private var bridge = TerminalBridge()
    @State private var activeHost: SSHHostConfig?
    @State private var editingHost: SSHHostConfig?

    var body: some View {
        Group {
            switch session.state {
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
        // Leaving the screen drops the connection — iOS suspends sockets in
        // the background anyway, so a terminal can't survive navigation.
        .onDisappear { session.disconnect() }
    }

    // MARK: - Host list

    private var hostList: some View {
        Group {
            if store.hosts.isEmpty {
                ContentUnavailableView {
                    Label(settings.tr(.noHosts), systemImage: "server.rack")
                } description: {
                    Text(settings.tr(.sshHostsHint))
                }
            } else {
                List {
                    ForEach(store.hosts) { host in
                        HStack(spacing: 12) {
                            Image(systemName: "server.rack")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading) {
                                Text(host.displayName)
                                Text(verbatim: "\(host.username)@\(host.host):\(host.port)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        // Whole row is the tap target — no button capsule.
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if host.isConnectable { connect(to: host) }
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
            }
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

    // MARK: - Terminal

    private var terminalArea: some View {
        ZStack {
            TerminalView(bridge: bridge, fontSize: settings.terminalFontSize)
            if session.state == .connecting {
                ProgressView(settings.tr(.connecting))
                    .padding()
                    .background(.regularMaterial, in: .rect(cornerRadius: 12))
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(settings.tr(.disconnect), role: .destructive) {
                    session.disconnect()
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
            if let activeHost {
                Button(settings.tr(.retry)) { connect(to: activeHost) }
            }
            Button(settings.tr(.back)) { session.disconnect() }
        }
    }

    // MARK: - Connect

    private func connect(to host: SSHHostConfig) {
        guard let password = store.password(for: host), !password.isEmpty else {
            // No password saved yet — open the editor to collect it first.
            editingHost = host
            return
        }
        activeHost = host
        session.disconnect()
        session.onOutput = { [weak bridge] data in bridge?.write(data) }
        bridge.onInput = { [weak session] data in session?.send(data) }
        bridge.onResize = { [weak session] cols, rows in session?.resize(cols: cols, rows: rows) }
        session.connect(host: host, password: password)
    }
}

// MARK: - Host editor

/// Two-line editor: an `ssh` command line (parsed into host/port/user) and
/// a password. Everything is padded — no edge-to-edge Form rows.
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
                         ? "ssh \(host.username)@\(host.host) -p \(host.port)" : "ssh ")
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
                    TextField("ssh user@host -p 22", text: $command)
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
                    Text(verbatim: "\(parsed.username)@\(parsed.host):\(parsed.port)")
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
                .disabled(parsed == nil)
            }
        }
        .padding(20)
        .frame(minWidth: 400)
        #if os(macOS)
        .fixedSize()
        #endif
    }
}
