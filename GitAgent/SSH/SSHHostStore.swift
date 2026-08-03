//
//  SSHHostStore.swift
//  GitAgent
//
//  Saved SSH hosts (JSON in UserDefaults; credentials in the Keychain).
//

import Foundation

struct SSHConnectionHop: Sendable {
    let host: SSHHostConfig
    let credential: SSHConnectionCredential
}

enum SSHConnectionCredential: Sendable {
    case password(String)
    case ed25519PrivateKey(String)
}

struct SSHConnectionRoute: Sendable {
    /// Ordered from the directly reachable host to the final target.
    let hops: [SSHConnectionHop]

    var target: SSHHostConfig { hops[hops.count - 1].host }
}

private enum SSHConnectionRouteError: LocalizedError {
    case hostUnavailable
    case passwordMissing(String)
    case privateKeyMissing(String)
    case cycle

    var errorDescription: String? {
        switch self {
        case .hostUnavailable:
            L10n.resolveCurrent(.computerUnavailable)
        case .passwordMissing(let name):
            L10n.sshPasswordMissing(host: name)
        case .privateKeyMissing(let name):
            L10n.sshPrivateKeyMissing(host: name)
        case .cycle:
            L10n.resolveCurrent(.sshJumpHostCycle)
        }
    }
}

@Observable
final class SSHHostStore {
    private(set) var hosts: [SSHHostConfig] = []
    private static let defaultsKey = "sshHosts"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode([SSHHostConfig].self, from: data) {
            hosts = decoded
        }
    }

    func password(for host: SSHHostConfig) -> String? {
        KeychainHelper.readSSHPassword(hostID: host.id.uuidString)
    }

    func privateKey(for host: SSHHostConfig) -> String? {
        KeychainHelper.readSSHPrivateKey(hostID: host.id.uuidString)
    }

    /// Resolves a host and any configured jump chain into connection order.
    /// Every hop keeps its own Keychain credential and TOFU host-key identity.
    func connectionRoute(for target: SSHHostConfig) throws -> SSHConnectionRoute {
        var reverseHops: [SSHConnectionHop] = []
        var visited: Set<SSHHostConfig.ID> = []
        var current = target

        while true {
            guard visited.insert(current.id).inserted else {
                throw SSHConnectionRouteError.cycle
            }
            let credential: SSHConnectionCredential
            // A host with its own jumpHostID is reached through another SSH
            // connection and therefore always uses its Ed25519 credential.
            let authenticationKind: SSHAuthenticationKind = current.jumpHostID == nil
                ? current.resolvedAuthenticationKind
                : .ed25519Key
            switch authenticationKind {
            case .password:
                guard let password = password(for: current), !password.isEmpty else {
                    throw SSHConnectionRouteError.passwordMissing(current.displayName)
                }
                credential = .password(password)
            case .ed25519Key:
                guard let privateKey = privateKey(for: current), !privateKey.isEmpty else {
                    throw SSHConnectionRouteError.privateKeyMissing(current.displayName)
                }
                credential = .ed25519PrivateKey(privateKey)
            }
            reverseHops.append(SSHConnectionHop(host: current, credential: credential))

            guard let jumpHostID = current.jumpHostID else { break }
            guard let jumpHost = hosts.first(where: { $0.id == jumpHostID }) else {
                throw SSHConnectionRouteError.hostUnavailable
            }
            current = jumpHost
        }

        return SSHConnectionRoute(hops: reverseHops.reversed())
    }

    /// Excludes choices that would make the edited host depend on itself.
    func availableJumpHosts(for hostID: SSHHostConfig.ID) -> [SSHHostConfig] {
        hosts.filter { candidate in
            guard candidate.id != hostID else { return false }
            var visited: Set<SSHHostConfig.ID> = []
            var current: SSHHostConfig? = candidate
            while let host = current {
                guard host.id != hostID, visited.insert(host.id).inserted else { return false }
                current = host.jumpHostID.flatMap { jumpID in
                    hosts.first(where: { $0.id == jumpID })
                }
            }
            return true
        }
    }

    /// Inserts or updates a host. Non-empty credentials are stored in the
    /// Keychain; empty/nil values leave existing credentials untouched.
    func save(_ host: SSHHostConfig, password: String?, privateKey: String? = nil) {
        if let index = hosts.firstIndex(where: { $0.id == host.id }) {
            let previous = hosts[index]
            if previous.host != host.host || previous.port != host.port {
                HostKeyStore.remove(hostID: host.id)
            }
            hosts[index] = host
        } else {
            hosts.append(host)
        }
        persist()
        if let password, !password.isEmpty {
            KeychainHelper.save(sshPassword: password, hostID: host.id.uuidString)
        }
        if let privateKey, !privateKey.isEmpty {
            KeychainHelper.save(sshPrivateKey: privateKey, hostID: host.id.uuidString)
        }
    }

    func delete(_ host: SSHHostConfig) {
        hosts.removeAll { $0.id == host.id }
        for index in hosts.indices where hosts[index].jumpHostID == host.id {
            hosts[index].jumpHostID = nil
        }
        persist()
        KeychainHelper.deleteSSHPassword(hostID: host.id.uuidString)
        KeychainHelper.deleteSSHPrivateKey(hostID: host.id.uuidString)
        HostKeyStore.remove(hostID: host.id)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(hosts) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}
