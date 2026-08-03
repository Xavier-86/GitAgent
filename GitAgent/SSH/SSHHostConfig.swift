//
//  SSHHostConfig.swift
//  GitAgent
//
//  Saved SSH host model.
//

import Foundation

enum SSHAuthenticationKind: String, Codable, CaseIterable, Sendable {
    case password
    case ed25519Key
}

/// A saved SSH host. Only non-sensitive fields are persisted (JSON in
/// UserDefaults) — credentials live in the Keychain, keyed by `id`.
struct SSHHostConfig: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    /// Optional label; falls back to `user@host` for display.
    var name = ""
    var host = ""
    var port = 22
    var username = ""
    /// Nil decodes older saved hosts as password-based authentication.
    var authenticationKind: SSHAuthenticationKind?
    /// Optional saved host used as the first SSH hop. The target remains a
    /// standalone host with its own credentials and pinned host key.
    var jumpHostID: ID?

    var resolvedAuthenticationKind: SSHAuthenticationKind {
        authenticationKind ?? .password
    }

    var displayName: String {
        if !name.isEmpty { return name }
        return username.isEmpty ? host : "\(username)@\(host)"
    }

    /// The endpoint shown in the UI. Port 22 is SSH's implicit default and
    /// should not be rewritten into a command that did not specify a port.
    var connectionDescription: String {
        let destination = username.isEmpty ? host : "\(username)@\(host)"
        return port == 22 ? destination : "\(destination):\(port)"
    }

    var commandLine: String {
        let destination = username.isEmpty ? host : "\(username)@\(host)"
        return port == 22
            ? "ssh \(destination)"
            : "ssh \(destination) -p \(port)"
    }

    var isLocalhost: Bool {
        let normalized = host.lowercased()
        return normalized == "localhost" || normalized == "127.0.0.1" || normalized == "::1"
    }

    var locationDisplayName: String {
        // "This Mac" only makes sense on macOS — iOS has no local shell, so a
        // localhost SSH host there is just another (usually useless) host.
        #if os(macOS)
        isLocalhost ? "\(L10n.resolveCurrent(.thisMac)) — \(displayName)" : displayName
        #else
        displayName
        #endif
    }

    /// True when the entry has enough information to attempt a connection.
    var isConnectable: Bool { !host.isEmpty && !username.isEmpty }

    /// Parses an `ssh` command line — e.g.
    /// `ssh -o PubkeyAuthentication=no user@host -p 2222` — into a host
    /// config. Options are ignored except `-p` (port) and `-l` (login name);
    /// `user@` in the destination wins over `-l`. Returns nil without a
    /// usable destination.
    static func parse(command: String) -> SSHHostConfig? {
        // Flags that consume the following token.
        let flagsWithArg: Set<String> = ["-o", "-i", "-F", "-L", "-R", "-D", "-J", "-b", "-c", "-m", "-S", "-W"]
        let tokens = command.split(whereSeparator: \.isWhitespace).map(String.init)
        var config = SSHHostConfig()
        var foundDestination = false
        var i = 0
        while i < tokens.count {
            let token = tokens[i]
            defer { i += 1 }
            if token == "ssh" && i == 0 { continue }
            if token == "-p" {
                if i + 1 < tokens.count, let port = Int(tokens[i + 1]) { config.port = port }
                i += 1 // defer adds the other — skip the value token
                continue
            }
            if token.hasPrefix("-p"), token.count > 2, let port = Int(token.dropFirst(2)) {
                config.port = port
                continue
            }
            if token == "-l" {
                if i + 1 < tokens.count { config.username = tokens[i + 1] }
                i += 1
                continue
            }
            if flagsWithArg.contains(token) {
                i += 1 // skip the option's value
                continue
            }
            if token.hasPrefix("-") || foundDestination { continue }
            // First positional token is the destination: [user@]host.
            foundDestination = true
            if let at = token.lastIndex(of: "@") {
                config.username = String(token[..<at])
                config.host = String(token[token.index(after: at)...])
            } else {
                config.host = token
            }
        }
        guard config.isConnectable else { return nil }
        return config
    }
}
