//
//  HostKeyStore.swift
//  GitAgent
//
//  Trust-on-first-use host-key validation shared by every SSH channel.
//

import Foundation
import Citadel
import NIO
@preconcurrency import NIOSSH

struct SSHHostKeyChangedError: LocalizedError {
    var errorDescription: String? {
        L10n.resolveCurrent(.sshHostKeyChanged)
    }
}

enum HostKeyStore {
    private static let defaultsPrefix = "sshHostKey."
    private static let lock = NSLock()

    static func validator(for hostID: SSHHostConfig.ID) -> SSHHostKeyValidator {
        .custom(TrustOnFirstUseValidator(hostID: hostID))
    }

    static func remove(hostID: SSHHostConfig.ID) {
        lock.lock()
        defer { lock.unlock() }
        UserDefaults.standard.removeObject(forKey: key(for: hostID))
    }

    fileprivate static func validate(_ hostKey: NIOSSHPublicKey,
                                     for hostID: SSHHostConfig.ID) throws {
        lock.lock()
        defer { lock.unlock() }

        let presented = String(openSSHPublicKey: hostKey)
        if let saved = UserDefaults.standard.string(forKey: key(for: hostID)) {
            let trusted = try NIOSSHPublicKey(openSSHPublicKey: saved)
            guard trusted == hostKey else { throw SSHHostKeyChangedError() }
        } else {
            UserDefaults.standard.set(presented, forKey: key(for: hostID))
        }
    }

    private static func key(for hostID: SSHHostConfig.ID) -> String {
        defaultsPrefix + hostID.uuidString
    }
}

private final class TrustOnFirstUseValidator: NIOSSHClientServerAuthenticationDelegate,
                                                 @unchecked Sendable {
    private let hostID: SSHHostConfig.ID

    init(hostID: SSHHostConfig.ID) {
        self.hostID = hostID
    }

    func validateHostKey(hostKey: NIOSSHPublicKey,
                         validationCompletePromise: EventLoopPromise<Void>) {
        do {
            // First contact pins the exact public key. All later connections
            // reject a changed key instead of silently accepting it.
            try HostKeyStore.validate(hostKey, for: hostID)
            validationCompletePromise.succeed(())
        } catch {
            validationCompletePromise.fail(error)
        }
    }
}
