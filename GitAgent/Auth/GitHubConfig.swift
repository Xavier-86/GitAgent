//
//  GitHubConfig.swift
//  GitAgent
//

import Foundation

enum GitHubConfig {
    /// Client ID of your GitHub OAuth App. The value lives in the gitignored
    /// GitAgent/Auth/LocalSecrets.swift (see README, "Setup").
    static let clientID = GitAgentSecrets.clientID

    /// repo: read private/public repositories; read.user: read the user profile
    static let scope = "repo read:user"

    static let apiBase = URL(string: "https://api.github.com")!
    static let deviceCodeURL = URL(string: "https://github.com/login/device/code")!
    static let accessTokenURL = URL(string: "https://github.com/login/oauth/access_token")!
    static let deviceVerificationURL = URL(string: "https://github.com/login/device")!
}
