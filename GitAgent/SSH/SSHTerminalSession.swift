//
//  SSHTerminalSession.swift
//  GitAgent
//
//  One SSH connection driving an interactive PTY shell on the remote host.
//

import Foundation
import Citadel
import NIO
import NIOSSH

/// Opens an SSH connection and runs an interactive shell behind a PTY. Output
/// bytes are forwarded via `onOutput`; keystrokes go back through `send(_:)`.
@MainActor
@Observable
final class SSHTerminalSession {
    private(set) var state: TerminalSessionState = .disconnected
    /// Remote output — wired to the terminal view by the owning screen.
    var onOutput: ((Data) -> Void)?

    private var connection: SSHConnection?
    private var writer: TTYStdinWriter?
    private var sessionTask: Task<Void, Never>?
    private var attemptID: UUID?

    var isConnected: Bool { state == .connected }

    func connect(route: SSHConnectionRoute, initialInput: Data? = nil) {
        guard state == .disconnected || isFailed else { return }
        let attemptID = UUID()
        self.attemptID = attemptID
        state = .connecting
        sessionTask = Task { [weak self] in
            var pendingConnection: SSHConnection?
            do {
                let connection = try await SSHConnection.connect(route: route)
                pendingConnection = connection
                guard let self, self.attemptID == attemptID else {
                    pendingConnection = nil
                    await connection.close()
                    return
                }
                try Task.checkCancellation()
                self.connection = connection
                pendingConnection = nil

                let pty = SSHChannelRequestEvent.PseudoTerminalRequest(
                    wantReply: true,
                    term: "xterm-256color",
                    terminalCharacterWidth: 80,
                    terminalRowHeight: 24,
                    terminalPixelWidth: 0,
                    terminalPixelHeight: 0,
                    terminalModes: .init([.ECHO: 1])
                )
                // OpenSSH servers commonly accept LANG/LC_* environment
                // requests. A UTF-8 locale stops tools such as macOS `ls`
                // from replacing non-ASCII filename characters with `?`.
                let environment = [
                    SSHChannelRequestEvent.EnvironmentRequest(
                        wantReply: false,
                        name: "LANG",
                        value: "C.UTF-8"
                    ),
                    SSHChannelRequestEvent.EnvironmentRequest(
                        wantReply: false,
                        name: "LC_CTYPE",
                        value: "C.UTF-8"
                    ),
                ]
                // withPTY runs until the shell exits or the channel dies —
                // this await lasts for the whole session.
                try await connection.client.withPTY(
                    pty,
                    environment: environment
                ) { inbound, outbound in
                    self.writer = outbound
                    self.state = .connected
                    if let initialInput {
                        try await outbound.write(ByteBuffer(bytes: initialInput))
                    }
                    do {
                        for try await event in inbound {
                            guard case .stdout(let buffer) = event else { continue }
                            self.onOutput?(Data(buffer.readableBytesView))
                        }
                    } catch {
                        // Channel closed mid-stream — treated as a disconnect below.
                    }
                    self.writer = nil
                    if self.attemptID == attemptID, self.state == .connected {
                        self.state = .disconnected
                    }
                }
                await connection.close()
                if self.connection === connection {
                    self.connection = nil
                }
            } catch is CancellationError {
                guard self?.attemptID == attemptID else { return }
                if let connection = self?.connection ?? pendingConnection {
                    self?.connection = nil
                    pendingConnection = nil
                    await connection.close()
                }
                self?.state = .disconnected
            } catch {
                guard self?.attemptID == attemptID else { return }
                if let connection = self?.connection ?? pendingConnection {
                    self?.connection = nil
                    pendingConnection = nil
                    await connection.close()
                }
                self?.state = .failed(error.localizedDescription)
            }
        }
    }

    /// Sends keystroke bytes to the remote shell's stdin.
    func send(_ data: Data) {
        guard let writer else { return }
        Task { try? await writer.write(ByteBuffer(bytes: data)) }
    }

    /// Reports the terminal's new size to the remote PTY.
    func resize(cols: Int, rows: Int) {
        guard let writer, cols > 0, rows > 0 else { return }
        Task { try? await writer.changeSize(cols: cols, rows: rows, pixelWidth: 0, pixelHeight: 0) }
    }

    func disconnect() {
        let connection = connection
        attemptID = nil
        sessionTask?.cancel()
        sessionTask = nil
        writer = nil
        self.connection = nil
        state = .disconnected
        if let connection {
            Task { await connection.close() }
        }
    }

    func fail(_ message: String) {
        disconnect()
        state = .failed(message)
    }

    private var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }
}

enum TerminalSessionState: Equatable {
    case disconnected
    case connecting
    case connected
    case failed(String)
}
