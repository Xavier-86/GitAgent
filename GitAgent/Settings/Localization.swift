//
//  Localization.swift
//  GitAgent
//

import Foundation

/// UI string table. The app UI is English-only.
enum L10n {
    enum Key {
        // Sidebar
        case myRepos, starred, searchRepos, viewUser, chat, logout, logoutConfirmMessage, settings
        case uiFontSize, markdownFontSize
        // Profile
        case profile, repositories, followers, following, contributions, contributionsLastYear
        // Kimi chat
        case kimiSection, kimiAPIKey, kimiBaseURL, kimiModel, provider, refreshModels, agentNeedKey
        case agentPlaceholder, agentError, chats, newChat, chatEmpty, chatGuideAt, chatGuideSlash, delete
        // Login
        case signIn, deviceCodePrompt, openAuthPage, openInBrowser, copyCode, waitingAuth, cancel
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
        .starred: "Starred",
        .searchRepos: "Search Repositories",
        .viewUser: "View User",
        .chat: "Chat",
        .profile: "Profile",
        .repositories: "Repositories",
        .followers: "Followers",
        .following: "Following",
        .contributions: "Contributions",
        .contributionsLastYear: "contributions in the last year",
        .kimiSection: "AI Chat",
        .kimiAPIKey: "API Key",
        .kimiBaseURL: "Base URL",
        .kimiModel: "Model",
        .provider: "Provider",
        .refreshModels: "Refresh Models",
        .agentNeedKey: "Enter your API key in Settings to start chatting",
        .agentPlaceholder: "Ask anything…",
        .agentError: "Request Failed",
        .chats: "Chats",
        .newChat: "New Chat",
        .chatEmpty: "Start a conversation",
        .chatGuideAt: "Type @ to reference a repository (adds its README)",
        .chatGuideSlash: "Type / after choosing a repository to reference files or folders",
        .delete: "Delete",
        .logout: "Sign Out",
        .logoutConfirmMessage: "Are you sure you want to sign out?",
        .settings: "Settings",
        .uiFontSize: "UI Font Size",
        .markdownFontSize: "Markdown Font Size",
        .signIn: "Sign in with GitHub",
        .deviceCodePrompt: "Enter this code on the authorization page to grant access:",
        .openAuthPage: "Authorize GitHub Access",
        .openInBrowser: "Open in Browser",
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
        .clientIDMissing: "Please set your OAuth App Client ID in LocalSecrets.swift first (see README).",
        .authCodeExpired: "The device code expired. Please try again.",
        .accessDenied: "Authorization was denied.",
        .authTimeout: "Authorization timed out. Please try again.",
        .unknownError: "Unknown error",
    ]
}
