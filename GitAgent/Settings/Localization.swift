//
//  Localization.swift
//  GitAgent
//

import Foundation

/// App-wide settings, persisted in UserDefaults.
@Observable
final class AppSettings {
    static let fontSizeKey = "fontSize"

    /// Base font size (points) for rendered Markdown content.
    var fontSize: Int {
        didSet { UserDefaults.standard.set(fontSize, forKey: Self.fontSizeKey) }
    }

    init() {
        let storedSize = UserDefaults.standard.integer(forKey: Self.fontSizeKey)
        fontSize = storedSize > 0 ? storedSize : 16
    }

    /// UI string for a key. The app UI is English-only.
    func tr(_ key: L10n.Key) -> String {
        L10n.resolveCurrent(key)
    }
}

/// UI string table. The app UI is English-only.
enum L10n {
    enum Key {
        // Sidebar
        case myRepos, searchRepos, viewUser, logout, settings, fontSize
        // Login
        case appTagline, signIn, deviceCodePrompt, openAuthPage, copyCode, waitingAuth, cancel
        // Loading / states
        case loading, loadingReadme, searching, retry, loadFailed, searchFailed
        case noRepos, emptyFolder, noSearchResults, searchReposHint, searchUserHint
        case searchKeywordPrompt, usernamePrompt, noReadme, view, files
        // In-app web viewer
        case done
        // Errors
        case unauthorized, rateLimited, invalidResponse, clientIDMissing
        case authCodeExpired, accessDenied, authTimeout, unknownError
    }

    /// Resolve a key (also usable from layers without access to AppSettings).
    static func resolveCurrent(_ key: Key) -> String {
        strings[key] ?? ""
    }

    static func requestFailed(status: Int, message: String) -> String {
        String(format: "Request failed (%d): %@", status, message)
    }

    private static let strings: [Key: String] = [
        .myRepos: "My Repositories",
        .searchRepos: "Search Repositories",
        .viewUser: "View User",
        .logout: "Sign Out",
        .settings: "Settings",
        .fontSize: "Font Size",
        .appTagline: "Sign in with GitHub to browse repositories and read Markdown",
        .signIn: "Sign in with GitHub",
        .deviceCodePrompt: "Enter this code on the authorization page to grant access:",
        .openAuthPage: "Authorize GitHub Access",
        .copyCode: "Copy Code",
        .waitingAuth: "Waiting for authorization…",
        .cancel: "Cancel",
        .loading: "Loading…",
        .loadingReadme: "Loading README…",
        .searching: "Searching…",
        .retry: "Retry",
        .loadFailed: "Failed to Load",
        .searchFailed: "Search Failed",
        .noRepos: "No Repositories Found",
        .emptyFolder: "Empty Folder",
        .noSearchResults: "No Matching Repositories",
        .searchReposHint: "Enter keywords to search GitHub repositories",
        .searchUserHint: "Enter a GitHub username to view their public repositories",
        .searchKeywordPrompt: "Repository name / keywords",
        .usernamePrompt: "GitHub username",
        .noReadme: "This repository has no README",
        .view: "View",
        .files: "Files",
        .done: "Done",
        .unauthorized: "Session expired. Please sign in again.",
        .rateLimited: "Too many requests. GitHub rate limit reached, please try again later.",
        .invalidResponse: "The server returned data that could not be parsed.",
        .clientIDMissing: "Please set your OAuth App Client ID in GitHubConfig.swift first.",
        .authCodeExpired: "The device code expired. Please try again.",
        .accessDenied: "Authorization was denied.",
        .authTimeout: "Authorization timed out. Please try again.",
        .unknownError: "Unknown error",
    ]
}
