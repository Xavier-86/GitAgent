//
//  Models.swift
//  GitAgent
//

import Foundation

struct GitHubUser: Codable, Hashable {
    let login: String
    let name: String?
    let avatarURL: URL?
    let bio: String?
    let publicRepos: Int
    let followers: Int
    let following: Int

    enum CodingKeys: String, CodingKey {
        case login, name, bio, followers, following
        case avatarURL = "avatar_url"
        case publicRepos = "public_repos"
    }
}

struct Repo: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let fullName: String
    let description: String?
    let owner: RepoOwner
    let isPrivate: Bool
    let htmlURL: URL?
    let language: String?
    let stargazersCount: Int
    let updatedAt: Date?
    let defaultBranch: String

    enum CodingKeys: String, CodingKey {
        case id, name, description, owner, language
        case fullName = "full_name"
        case isPrivate = "private"
        case htmlURL = "html_url"
        case stargazersCount = "stargazers_count"
        case updatedAt = "updated_at"
        case defaultBranch = "default_branch"
    }
}

struct RepoOwner: Codable, Hashable {
    let login: String
    let avatarURL: URL?

    enum CodingKeys: String, CodingKey {
        case login
        case avatarURL = "avatar_url"
    }
}

/// Entry returned by /repos/{owner}/{repo}/contents (a directory or a file).
struct RepoContent: Codable, Identifiable, Hashable {
    let name: String
    let path: String
    let type: ContentType
    let size: Int
    let downloadURL: URL?
    let htmlURL: URL?
    /// For submodules: the linked repository's git URL (any form: https,
    /// SCP-style SSH, or relative). Only present on direct single-path
    /// lookups, not in directory listings.
    let submoduleGitURL: String?

    var id: String { path }

    enum ContentType: String, Codable, Hashable {
        case dir, file, symlink, submodule
    }

    enum CodingKeys: String, CodingKey {
        case name, path, type, size
        case downloadURL = "download_url"
        case htmlURL = "html_url"
        case submoduleGitURL = "submodule_git_url"
    }

    var isMarkdown: Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return ext == "md" || ext == "markdown"
    }

    /// GitHub misreports submodules as plain `"type": "file"` in directory
    /// listings — only a direct single-path lookup returns `"submodule"`.
    /// In a listing, a submodule is the entry with no download URL whose
    /// html_url points at another repository's tree.
    var isSubmodule: Bool {
        type == .submodule || (type == .file && downloadURL == nil && htmlRepoRef != nil)
    }

    /// Type to switch on in the UI: upgrades listing entries that GitHub
    /// mislabels as files (submodules) to `.submodule`.
    var effectiveType: ContentType { isSubmodule ? .submodule : type }

    /// owner/name parsed from an html_url of the form
    /// `https://github.com/owner/repo/tree/<sha>` (present on submodules).
    private var htmlRepoRef: RepoLinkRef? {
        guard let parts = htmlURL?.pathComponents, parts.count >= 4,
              parts[3] == "tree" else { return nil }
        return RepoLinkRef(owner: parts[1], name: parts[2])
    }

    /// For submodules: owner/name of the linked repository. Prefers the
    /// normalized html_url; otherwise parses `submodule_git_url` (any form:
    /// `https://host/owner/repo.git`, SCP-style SSH `git@host:owner/repo.git`,
    /// or relative `../repo.git` resolved against `fallbackOwner`).
    func submoduleRepoRef(fallbackOwner: String) -> RepoLinkRef? {
        guard isSubmodule else { return nil }
        if let htmlRepoRef { return htmlRepoRef }
        guard let raw = submoduleGitURL else { return nil }
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasSuffix(".git") { s = String(s.dropLast(4)) }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let parts = s.split(whereSeparator: { $0 == "/" || $0 == ":" }).map(String.init)
        guard parts.count >= 2 else { return nil }
        let owner = parts[parts.count - 2] == ".." ? fallbackOwner : parts[parts.count - 2]
        return RepoLinkRef(owner: owner, name: parts[parts.count - 1])
    }
}

/// Wrapper of the search endpoint response.
struct RepoSearchResult: Decodable {
    let items: [Repo]
}

/// The green-square contribution calendar shown on GitHub profiles.
struct ContributionCalendar {
    struct Day {
        let date: String
        let count: Int
        /// 0 (none) … 4 (fourth quartile), matching GitHub's color scale.
        let level: Int
    }
    let totalContributions: Int
    /// Up to 53 weeks, each with up to 7 days (Sunday first).
    let weeks: [[Day]]
}

// MARK: - Device Flow

struct DeviceCodeResponse: Decodable {
    let deviceCode: String
    let userCode: String
    let verificationURI: URL
    let expiresIn: Int
    let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURI = "verification_uri"
        case expiresIn = "expires_in"
        case interval
    }
}

struct AccessTokenResponse: Decodable {
    let accessToken: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case error
    }
}
