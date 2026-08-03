//
//  SSHEd25519Credential.swift
//  GitAgent
//
//  Generates an app-owned Ed25519 key and its OpenSSH public-key line.
//

import CryptoKit
import Foundation

enum SSHEd25519Credential {
    static func generatePrivateKey() -> String {
        let key = Curve25519.Signing.PrivateKey()
        return key.rawRepresentation.base64EncodedString()
    }

    static func privateKey(from encoded: String) throws -> Curve25519.Signing.PrivateKey {
        guard let data = Data(base64Encoded: encoded) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return try Curve25519.Signing.PrivateKey(rawRepresentation: data)
    }

    static func publicKeyLine(from encoded: String) throws -> String {
        let key = try privateKey(from: encoded)
        var blob = Data()
        blob.appendSSHString(Data("ssh-ed25519".utf8))
        blob.appendSSHString(key.publicKey.rawRepresentation)
        return "ssh-ed25519 \(blob.base64EncodedString()) GitAgent"
    }
}

private extension Data {
    mutating func appendSSHString(_ value: Data) {
        var length = UInt32(value.count).bigEndian
        Swift.withUnsafeBytes(of: &length) { append(contentsOf: $0) }
        append(value)
    }
}
