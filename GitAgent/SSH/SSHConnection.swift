//
//  SSHConnection.swift
//  GitAgent
//
//  Opens a direct SSH client or a chain of Citadel jump-host clients.
//

import Citadel
import Foundation
import NIO

enum SSHConnectionError: LocalizedError {
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

/// A reference-counted lease on a shared SSH route. Terminal, repository
/// browsing, verification, and agents can open independent SSH channels on an
/// already authenticated connection instead of creating another TCP tunnel.
final class SSHConnection {
    /// Repeats operations interrupted by transport loss until they succeed or
    /// their caller task is cancelled. Permanent authentication, host-key,
    /// command, and application-level errors are returned immediately.
    static func retryingTransientFailure<T>(
        operation: @escaping () async throws -> T
    ) async throws -> T {
        var delayNanoseconds: UInt64 = 500_000_000
        while true {
            try Task.checkCancellation()
            do {
                return try await operation()
            } catch {
                guard isTransientFailure(error) else { throw error }
                try await Task.sleep(nanoseconds: delayNanoseconds)
                delayNanoseconds = min(delayNanoseconds * 2, 8_000_000_000)
            }
        }
    }

    static func isTransientFailure(_ error: Error) -> Bool {
        if error is IOError || error is ChannelError { return true }
        if let connectionError = error as? SSHConnectionError {
            switch connectionError {
            case .connectionFailed: return true
            case .authenticationFailed: return false
            }
        }
        if let citadelError = error as? CitadelError {
            switch citadelError {
            case .channelCreationFailed, .channelFailure: return true
            default: return false
            }
        }
        return false
    }

    private struct RouteKey: Hashable {
        struct Hop: Hashable {
            let id: SSHHostConfig.ID
            let host: String
            let port: Int
            let username: String
        }

        let hops: [Hop]

        init(route: SSHConnectionRoute) {
            hops = route.hops.map {
                Hop(id: $0.host.id, host: $0.host.host, port: $0.host.port,
                    username: $0.host.username)
            }
        }
    }

    private final class Transport {
        let clients: [SSHClient]
        var client: SSHClient { clients[clients.count - 1] }
        var isConnected: Bool { clients.allSatisfy(\.isConnected) }

        init(clients: [SSHClient]) {
            self.clients = clients
        }

        func close() async {
            for client in clients.reversed() {
                try? await client.close()
            }
        }
    }

    private struct PoolEntry {
        let transport: Transport
        var leaseCount: Int
    }

    private static let poolLock = NSLock()
    private static var pool: [RouteKey: PoolEntry] = [:]

    var client: SSHClient { transport.client }
    private let routeKey: RouteKey
    private let transport: Transport
    private let closeLock = NSLock()
    private var isClosed = false

    private init(routeKey: RouteKey, transport: Transport) {
        self.routeKey = routeKey
        self.transport = transport
    }

    static func connect(route: SSHConnectionRoute) async throws -> SSHConnection {
        let routeKey = RouteKey(route: route)
        let retained = retainConnectedTransport(for: routeKey)
        if let staleTransport = retained.stale {
            await staleTransport.close()
        }
        if let transport = retained.connected {
            return SSHConnection(routeKey: routeKey, transport: transport)
        }

        let candidate = try await makeTransport(route: route)
        let installed = installOrRetain(candidate, for: routeKey)
        for unusedTransport in installed.unused {
            await unusedTransport.close()
        }
        return SSHConnection(routeKey: routeKey, transport: installed.transport)
    }

    private static func makeTransport(route: SSHConnectionRoute) async throws -> Transport {
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
                let nextClient = try await connect(
                    settings: settings,
                    through: clients.last,
                    hostName: hop.host.displayName
                )
                clients.append(nextClient)
            }
            return Transport(clients: clients)
        } catch {
            for client in clients.reversed() {
                try? await client.close()
            }
            throw error
        }
    }

    func close() async {
        guard markClosed() else { return }
        if let transportToClose = Self.release(transport, for: routeKey) {
            await transportToClose.close()
        }
    }

    /// Removes a broken transport from the shared pool even when another
    /// lease still references it. Those leases observe the socket close and
    /// reconnect instead of keeping a half-dead connection reusable.
    func invalidate() async {
        guard markClosed() else { return }
        if let transportToClose = Self.invalidate(transport, for: routeKey) {
            await transportToClose.close()
        }
    }

    private func markClosed() -> Bool {
        closeLock.lock()
        defer { closeLock.unlock() }
        guard !isClosed else { return false }
        isClosed = true
        return true
    }

    private static func retainConnectedTransport(
        for routeKey: RouteKey
    ) -> (connected: Transport?, stale: Transport?) {
        let staleTransport: Transport?
        let connectedTransport: Transport?

        poolLock.lock()
        defer { poolLock.unlock() }
        if var entry = pool[routeKey], entry.transport.isConnected {
            entry.leaseCount += 1
            pool[routeKey] = entry
            connectedTransport = entry.transport
            staleTransport = nil
        } else {
            staleTransport = pool.removeValue(forKey: routeKey)?.transport
            connectedTransport = nil
        }
        return (connectedTransport, staleTransport)
    }

    /// Atomically resolves simultaneous first connections for the same route.
    /// Exactly one transport enters the pool; all other candidates are closed.
    private static func installOrRetain(
        _ candidate: Transport,
        for routeKey: RouteKey
    ) -> (transport: Transport, unused: [Transport]) {
        poolLock.lock()
        defer { poolLock.unlock() }

        if var entry = pool[routeKey], entry.transport.isConnected {
            entry.leaseCount += 1
            pool[routeKey] = entry
            return (entry.transport, [candidate])
        }

        let staleTransport = pool.removeValue(forKey: routeKey)?.transport
        pool[routeKey] = PoolEntry(transport: candidate, leaseCount: 1)
        return (candidate, staleTransport.map { [$0] } ?? [])
    }

    private static func release(
        _ transport: Transport,
        for routeKey: RouteKey
    ) -> Transport? {
        poolLock.lock()
        defer { poolLock.unlock() }

        guard var entry = pool[routeKey], entry.transport === transport else {
            return nil
        }
        entry.leaseCount -= 1
        if entry.leaseCount == 0 {
            pool[routeKey] = nil
            return entry.transport
        }
        pool[routeKey] = entry
        return nil
    }

    private static func invalidate(
        _ transport: Transport,
        for routeKey: RouteKey
    ) -> Transport? {
        poolLock.lock()
        defer { poolLock.unlock() }
        guard let entry = pool[routeKey], entry.transport === transport else {
            return nil
        }
        pool[routeKey] = nil
        return entry.transport
    }

    /// A socket-level NIO failure can be transient while a tunnel endpoint is
    /// changing paths. Retry it once, but never retry authentication or host-key
    /// failures. Concrete IOError formatting preserves errno and operation.
    private static func connect(
        settings: SSHClientSettings,
        through previous: SSHClient?,
        hostName: String
    ) async throws -> SSHClient {
        for attempt in 0...1 {
            do {
                if let previous {
                    return try await previous.jump(to: settings)
                }
                return try await SSHClient.connect(to: settings)
            } catch SSHClientError.allAuthenticationOptionsFailed {
                throw SSHConnectionError.authenticationFailed(hostName)
            } catch {
                if attempt == 0, error is IOError {
                    try await Task.sleep(for: .milliseconds(250))
                    continue
                }
                let reason: String
                if let ioError = error as? IOError {
                    reason = ioError.localizedDescription
                } else if let localizedError = error as? LocalizedError,
                          let description = localizedError.errorDescription {
                    reason = description
                } else {
                    reason = String(describing: error)
                }
                throw SSHConnectionError.connectionFailed(host: hostName, reason: reason)
            }
        }
        preconditionFailure("SSH connection retry loop exited unexpectedly")
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
