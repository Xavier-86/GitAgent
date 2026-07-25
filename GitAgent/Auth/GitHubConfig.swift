//
//  GitHubConfig.swift
//  GitAgent
//

import Foundation

enum GitHubConfig {
    /// Register an OAuth App at https://github.com/settings/developers,
    /// enable "Device Flow" in its settings, then paste the Client ID here.
    static let clientID = "Ov23liJ8WQHNZeoWbe3j"

    /// repo: read private/public repositories; read.user: read the user profile
    static let scope = "repo read:user"

    static let apiBase = URL(string: "https://api.github.com")!
    static let deviceCodeURL = URL(string: "https://github.com/login/device/code")!
    static let accessTokenURL = URL(string: "https://github.com/login/oauth/access_token")!
    static let deviceVerificationURL = URL(string: "https://github.com/login/device")!
}
