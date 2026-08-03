//
//  SSHConnection.swift
//  GitAgent
//
//  Opens a direct SSH client or a chain of Citadel jump-host clients.
//

import Citadel
import Foundation

private enum SSHConnectionError: LocalizedError {
    case authenticationFailed(String)
    case connectionFailed(host: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .authenticationFailed(let host):
            L10n.sshAuthenticationFailed(host: host)
        case .connectionFailed(let host, let reason):
            L10n.sshConnectionFailed(host: host, reason: reason)
        }
    }
}

/// Owns every SSH client in a route so a target's direct-tcpip channel stays
/// alive for as long as the final client is in use.
final class SSHConnection {
    let client: SSHClient
    private let clients: [SSHClient]

    private init(clients: [SSHClient]) {
        self.clients = clients
        client = clients[clients.count - 1]
    }

    static func connect(route: SSHConnectionRoute) async throws -> SSHConnection {
        precondition(!route.hops.isEmpty)
        var clients: [SSHClient] = []

        do {
            for hop in route.hops {
                try Task.checkCancellation()
                let settings = SSHClientSettings(
                    host: hop.host.host,
                    port: hop.host.port,
                    authenticationMethod: try authenticationMethod(for: hop),
                    hostKeyValidator: HostKeyStore.validator(for: hop.host.id)
                )
                let nextClient: SSHClient
                do {
                    if let previous = clients.last {
                        nextClient = try await previous.jump(to: settings)
                    } else {
                        nextClient = try await SSHClient.connect(to: settings)
                    }
                } catch SSHClientError.allAuthenticationOptionsFailed {
                    throw SSHConnectionError.authenticationFailed(hop.host.displayName)
                } catch {
                    throw SSHConnectionError.connectionFailed(
                        host: hop.host.displayName,
                        reason: error.localizedDescription
                    )
                }
                clients.append(nextClient)
            }
            return SSHConnection(clients: clients)
        } catch {
            for client in clients.reversed() {
                try? await client.close()
            }
            throw error
        }
    }

    func close() async {
        for client in clients.reversed() {
            try? await client.close()
        }
    }

    private static func authenticationMethod(
        for hop: SSHConnectionHop
    ) throws -> @Sendable () -> SSHAuthenticationMethod {
        switch hop.credential {
        case .password(let password):
            return {
                .passwordBased(username: hop.host.username, password: password)
            }
        case .ed25519PrivateKey(let encoded):
            let privateKey = try SSHEd25519Credential.privateKey(from: encoded)
            return {
                .ed25519(username: hop.host.username, privateKey: privateKey)
            }
        }
    }
}
