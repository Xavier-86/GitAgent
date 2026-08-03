//
//  KeychainHelper.swift
//  GitAgent
//
//  Created by XuMingyuan on 2026/7/25.
//

import Foundation
import Security

/// Stores secrets (GitHub access token, Kimi API key) in the system Keychain
/// (shared by iOS and macOS).
enum KeychainHelper {
    private static let service = "com.gitagent.github"
    private static let githubAccount = "access-token"
    private static let kimiAccount = "kimi-api-key"

    // MARK: - GitHub token

    static func save(token: String) { save(token, account: githubAccount) }
    static func readToken() -> String? { read(account: githubAccount) }
    static func deleteToken() { delete(account: githubAccount) }

    // MARK: - Kimi API key

    static func save(kimiAPIKey: String) { save(kimiAPIKey, account: kimiAccount) }
    static func readKimiAPIKey() -> String? { read(account: kimiAccount) }
    static func deleteKimiAPIKey() { delete(account: kimiAccount) }

    // MARK: - SSH host passwords (keyed by host config UUID)

    static func save(sshPassword: String, hostID: String) { save(sshPassword, account: "ssh-password-\(hostID)") }
    static func readSSHPassword(hostID: String) -> String? { read(account: "ssh-password-\(hostID)") }
    static func deleteSSHPassword(hostID: String) { delete(account: "ssh-password-\(hostID)") }

    // MARK: - SSH Ed25519 private keys (base64 raw representation)

    static func save(sshPrivateKey: String, hostID: String) { save(sshPrivateKey, account: "ssh-private-key-\(hostID)") }
    static func readSSHPrivateKey(hostID: String) -> String? { read(account: "ssh-private-key-\(hostID)") }
    static func deleteSSHPrivateKey(hostID: String) { delete(account: "ssh-private-key-\(hostID)") }

    // MARK: - Generic plumbing

    private static func save(_ value: String, account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        SecItemAdd(attributes as CFDictionary, nil)
    }

    private static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
