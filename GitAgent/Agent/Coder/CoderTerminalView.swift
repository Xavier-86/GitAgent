//
//  CoderTerminalView.swift
//  GitAgent
//
//  Full interactive terminal attached to a Coder session's tmux session,
//  wired exactly like SSHView's terminal: a TerminalBridge bound to an
//  SSHTerminalSession (remote) or LocalTerminalSession (this Mac), with the
//  `tmux attach` line injected once the PTY is up.
//

import SwiftUI

struct CoderTerminalView: View {
  @Environment(AppSettings.self) private var settings
  @Environment(CoderStore.self) private var coder
  @Environment(SSHHostStore.self) private var hosts
  @Environment(\.dismiss) private var dismiss

  let recordID: CoderSessionRecord.ID

  @State private var bridge = TerminalBridge()
  @State private var session = SSHTerminalSession()
  @State private var activeTerminal: ActiveTerminalKind = .ssh
  #if os(macOS)
    @State private var localSession = LocalTerminalSession()
  #endif

  private enum ActiveTerminalKind {
    case ssh
    case local
  }

  private var record: CoderSessionRecord? {
    coder.record(recordID)
  }

  private var terminalState: TerminalSessionState {
    #if os(macOS)
      if activeTerminal == .local {
        return localSession.state
      }
    #endif
    return session.state
  }

  var body: some View {
    Group {
      switch terminalState {
      case .disconnected, .connecting, .connected:
        terminalArea
      case .failed(let message):
        failedView(message)
      }
    }
    .navigationTitle(record?.repositoryFullName ?? settings.tr(.coder))
    #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
    #endif
    .onAppear {
      // Viewing the session consumes its completion marker.
      coder.clearTurnFinished(recordID)
      connect()
    }
    // The tmux session ended (killed or detached and the shell exited):
    // the PTY closed, so pop back to the session list.
    .onChange(of: terminalState) { _, state in
      if state == .disconnected { dismiss() }
    }
    .onDisappear {
      session.disconnect()
      #if os(macOS)
        localSession.disconnect()
      #endif
    }
  }

  private var terminalArea: some View {
    ZStack {
      TerminalView(bridge: bridge, fontSize: settings.terminalFontSize)
      if terminalState == .connecting {
        ProgressView(settings.tr(.connecting))
          .padding()
          .background(.regularMaterial, in: .rect(cornerRadius: 12))
      }
    }
    .fontSizeShortcuts(
      9...24,
      get: { settings.terminalFontSize },
      set: { settings.terminalFontSize = $0 }
    )
  }

  private func failedView(_ message: String) -> some View {
    ContentUnavailableView {
      Label(settings.tr(.connectionFailed), systemImage: "exclamationmark.triangle")
    } description: {
      Text(message)
    } actions: {
      Button(settings.tr(.retry)) { reconnect() }
      Button(settings.tr(.back)) { dismiss() }
    }
  }

  // MARK: - Connect

  /// The line typed into the fresh PTY: attach to the session's tmux
  /// session, then exit the shell when the attach ends (detach or kill) so
  /// the terminal page pops back on its own. The `; exit` stays on the same
  /// command line — as a separate line it would sit in the tty input buffer
  /// and tmux would forward it to the CLI inside the pane.
  private func attachInput(for record: CoderSessionRecord) -> Data {
    let session = "ga-coder-\(record.id.uuidString.lowercased())"
    return Data(
      "\(CoderTool.pathExport); \(CoderTool.tmux) attach -t '\(session)'; exit\n".utf8
    )
  }

  private func connect() {
    guard let record else { return }
    if let hostID = record.hostID {
      activeTerminal = .ssh
      guard let host = hosts.hosts.first(where: { $0.id == hostID }) else {
        session.fail(L10n.resolveCurrent(.computerUnavailable))
        return
      }
      do {
        let route = try hosts.connectionRoute(for: host)
        session.disconnect()
        bridge.reset()
        session.onOutput = { [weak bridge] data in bridge?.write(data) }
        bridge.onInput = { [weak session] data in session?.send(data) }
        bridge.onResize = { [weak session] cols, rows in
          session?.resize(cols: cols, rows: rows)
        }
        session.connect(route: route, initialInput: attachInput(for: record))
      } catch {
        session.fail(error.localizedDescription)
      }
      return
    }
    #if os(macOS)
      activeTerminal = .local
      localSession.disconnect()
      bridge.reset()
      localSession.onOutput = { [weak bridge] data in bridge?.write(data) }
      bridge.onInput = { [weak localSession] data in localSession?.send(data) }
      bridge.onResize = { [weak localSession] cols, rows in
        localSession?.resize(cols: cols, rows: rows)
      }
      localSession.connect()
      // connect() is synchronous: the PTY is up when it returns, and input
      // bytes wait in the tty buffer until the shell reads them.
      localSession.send(attachInput(for: record))
    #else
      session.fail(L10n.resolveCurrent(.coderLocalUnavailable))
    #endif
  }

  private func reconnect() {
    session.disconnect()
    #if os(macOS)
      localSession.disconnect()
    #endif
    connect()
  }
}
