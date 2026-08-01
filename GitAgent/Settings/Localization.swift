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
        case uiFontSize, markdownFontSize, terminalFontSize
        // Profile
        case profile, repositories, followers, following, contributions, contributionsLastYear
        case company, location, website, twitter, email, gists, joined
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
        // SSH terminal
        case terminal, localShell, noHosts, sshHostsHint, edit, connecting, disconnect, connectionFailed, back
        case sshName, sshCommand, sshCommandInvalid, sshPassword, sshHostEditorTitle, save
        // Repository locations
        case repositoryLocations, noRepositoryLocations, repositoryLocationsHint
        case addRepositoryLocation, computer, selectComputer, repositoryPath, repositoryPathHint
        case repositoryPathFooter, saveAndVerify, verify, verifying, connected, notConnected
        case computerUnavailable, sshPasswordMissing, repositoryPathMissing, notGitRepository
        case noGitHubRemote, repositoryRemoteUnreachable, invalidRepositoryProbe
        case agentConfigured, agentNotConfigured, thisMac
        case addSSHHostFirst, chooseFolder, localRepositoryPathFooter
        case localRepositoryAccessDenied, folderSelectionFailed
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

    static func repositoryMismatch(expected: String, found: String) -> String {
        "Expected \(expected), but the Git remote points to \(found)."
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
        .company: "Company",
        .location: "Location",
        .website: "Website",
        .twitter: "Twitter",
        .email: "Email",
        .gists: "Gists",
        .joined: "Joined",
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
        .terminalFontSize: "Terminal Font Size",
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
        .terminal: "Terminal",
        .localShell: "Local Shell",
        .noHosts: "No Saved Hosts",
        .sshHostsHint: "Add a Mac or Linux machine to open a remote shell over SSH",
        .edit: "Edit",
        .connecting: "Connecting…",
        .disconnect: "Disconnect",
        .connectionFailed: "Connection Failed",
        .back: "Back",
        .sshName: "Name (optional)",
        .sshCommand: "SSH Command",
        .sshCommandInvalid: "Expected e.g. ssh user@host -p 22",
        .sshPassword: "Password",
        .sshHostEditorTitle: "SSH Host",
        .save: "Save",
        .repositoryLocations: "Repository Locations",
        .noRepositoryLocations: "No Repository Locations",
        .repositoryLocationsHint: "Connect this GitHub repository to a working tree on this Mac or an SSH host.",
        .addRepositoryLocation: "Add Repository Location",
        .computer: "Computer",
        .selectComputer: "Select a computer",
        .repositoryPath: "Repository Path",
        .repositoryPathHint: "~/Developer/repository",
        .repositoryPathFooter: "The path is checked on the selected SSH host.",
        .localRepositoryPathFooter: "Choose the repository folder on this Mac to grant read access.",
        .saveAndVerify: "Save & Verify",
        .verify: "Verify",
        .verifying: "Verifying…",
        .connected: "Connected",
        .notConnected: "Not Connected",
        .computerUnavailable: "Computer Not Available",
        .sshPasswordMissing: "No SSH password is saved for this computer.",
        .repositoryPathMissing: "The specified directory does not exist.",
        .notGitRepository: "The specified directory is not a Git working tree.",
        .noGitHubRemote: "The working tree has no GitHub remote.",
        .repositoryRemoteUnreachable: "The Git remote could not be reached from this computer.",
        .invalidRepositoryProbe: "The computer returned an invalid repository status.",
        .agentConfigured: "Agent repository location connected",
        .agentNotConfigured: "Agent repository location not connected",
        .thisMac: "This Mac",
        .addSSHHostFirst: "Add an SSH host in Terminal before configuring a repository location.",
        .chooseFolder: "Choose…",
        .localRepositoryAccessDenied: "GitAgent can no longer access this folder. Delete this location and choose the folder again.",
        .folderSelectionFailed: "Could not access the selected folder",
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
