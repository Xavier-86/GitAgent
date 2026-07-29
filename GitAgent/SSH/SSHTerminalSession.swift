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

/// Opens an SSH connection (password auth) and runs an interactive shell
/// behind a PTY. Output bytes are forwarded via `onOutput`; keystrokes go
/// back through `send(_:)`.
@Observable
final class SSHTerminalSession {
    enum State: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)
    }

    private(set) var state: State = .disconnected
    /// Remote output — wired to the terminal view by the owning screen.
    var onOutput: ((Data) -> Void)?

    private var client: SSHClient?
    private var writer: TTYStdinWriter?
    private var sessionTask: Task<Void, Never>?

    var isConnected: Bool { state == .connected }

    func connect(host: SSHHostConfig, password: String) {
        guard state == .disconnected || isFailed else { return }
        state = .connecting
        sessionTask = Task { [weak self] in
            do {
                let settings = SSHClientSettings(
                    host: host.host,
                    port: host.port,
                    authenticationMethod: {
                        .passwordBased(username: host.username, password: password)
                    },
                    // TODO: TOFU host-key verification with a fingerprint
                    // confirmation UI — never ship `.acceptAnything()` silently.
                    hostKeyValidator: .acceptAnything()
                )
                let client = try await SSHClient.connect(to: settings)
                guard let self else { return }
                try Task.checkCancellation()
                self.client = client

                let pty = SSHChannelRequestEvent.PseudoTerminalRequest(
                    wantReply: true,
                    term: "xterm-256color",
                    terminalCharacterWidth: 80,
                    terminalRowHeight: 24,
                    terminalPixelWidth: 0,
                    terminalPixelHeight: 0,
                    terminalModes: .init([.ECHO: 1])
                )
                // withPTY runs until the shell exits or the channel dies —
                // this await lasts for the whole session.
                try await client.withPTY(pty) { inbound, outbound in
                    self.writer = outbound
                    self.state = .connected
                    do {
                        for try await event in inbound {
                            guard case .stdout(let buffer) = event else { continue }
                            self.onOutput?(Data(buffer.readableBytesView))
                        }
                    } catch {
                        // Channel closed mid-stream — treated as a disconnect below.
                    }
                    self.writer = nil
                    if self.state == .connected { self.state = .disconnected }
                }
            } catch is CancellationError {
                self?.state = .disconnected
            } catch {
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
        sessionTask?.cancel()
        sessionTask = nil
        writer = nil
        client = nil
        state = .disconnected
    }

    private var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }
}
