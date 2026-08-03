//
//  SSHHostStore.swift
//  GitAgent
//
//  Saved SSH hosts (JSON in UserDefaults; passwords in the Keychain).
//

import Foundation

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

    /// Inserts or updates a host. A non-empty password is stored in the
    /// Keychain; an empty/nil one leaves any existing password untouched.
    func save(_ host: SSHHostConfig, password: String?) {
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
    }

    func delete(_ host: SSHHostConfig) {
        hosts.removeAll { $0.id == host.id }
        persist()
        KeychainHelper.deleteSSHPassword(hostID: host.id.uuidString)
        HostKeyStore.remove(hostID: host.id)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(hosts) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}
