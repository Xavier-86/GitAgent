//
//  SSHHostConfig.swift
//  GitAgent
//
//  Saved SSH host model.
//

import Foundation

/// A saved SSH host. Only non-sensitive fields are persisted (JSON in
/// UserDefaults) — the password lives in the Keychain, keyed by `id`.
struct SSHHostConfig: Codable, Identifiable, Hashable {
    var id = UUID()
    /// Optional label; falls back to `user@host` for display.
    var name = ""
    var host = ""
    var port = 22
    var username = ""

    var displayName: String {
        if !name.isEmpty { return name }
        return username.isEmpty ? host : "\(username)@\(host)"
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
