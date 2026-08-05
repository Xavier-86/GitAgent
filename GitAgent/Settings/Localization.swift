//
//  Localization.swift
//  GitAgent
//

import Foundation

/// UI string table. The app UI is English-only.
enum L10n {
    enum Key {
        // Sidebar
        case myRepos, starred, searchRepos, viewUser, chat, agent, logout, logoutConfirmMessage
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
        case sshAuthentication, sshPasswordAuthentication, sshKeyAuthentication, sshPublicKey
        case copyPublicKey, copySSHSetupCommand, generateSSHKey, generateNewKey, sshPublicKeyHint
        case sshHostKeyChanged, sshJumpHost, sshDirectConnection, sshJumpHostHint, sshJumpHostCycle
        case sshJumpRequiresKey
        // Repository locations
        case repositoryLocations, noRepositoryLocations, repositoryLocationsHint
        case addRepositoryLocation, computer, selectComputer, repositoryPath, repositoryPathHint
        case repositoryPathFooter, saveAndVerify, verify, verifying, connected, notConnected
        case computerUnavailable, sshPasswordMissing, repositoryPathMissing, notGitRepository
        case noGitHubRemote, repositoryRemoteUnreachable, invalidRepositoryProbe
        case agentConfigured, agentNotConfigured, thisMac
        case addSSHHostFirst, chooseFolder, localRepositoryPathFooter
        case localRepositoryAccessDenied, folderSelectionFailed
        // Remote path picker
        case browse, selectThisFolder, directoryListingFailed
        // RepoLaunch deployment
        case repoLaunch, deployRepository
        case availableAgents, repoLaunchDescription, advancedOptions, noFolderSelected
        case repositoryURL, repositoryURLHint
        case gitReference, gitReferenceHint, deploymentTarget, destinationFolder
        case destinationPath, destinationName, chooseParentFolder, linkExistingRepository
        case deploymentCommands, setupCommands, buildCommands, testCommands, commandsOptionalHint
        case deploy, deploying, repoLaunchRunning, repoLaunchSucceeded, repoLaunchFailed
        case repoLaunchCancelled, repoLaunchInterrupted, repoLaunchInvalidURL
        case repoLaunchInvalidDestination, repoLaunchLocalUnavailable, repoLaunchInvalidResult
        case repoLaunchTmuxUnavailable, repoLaunchConnectionLost
        case repoLaunchCommit
        case stagePreflight, stageCheckout, stageSetup, stageBuild, stageTest, stageVerify
        // Coder agent
        case coder, coderDescription, coderTool, coderWorkingCopy, coderSelectLocation
        case coderNoLocations, coderNewSession, coderInitialPromptHint, coderStartSession
        case coderSessions, coderNoSessions, coderKillSession, coderTurnFinished
        case coderCreateFailed, coderToolUnavailable, coderLocalUnavailable
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

    static func sshVia(host: String) -> String {
        "Via \(host)"
    }

    static func sshPasswordMissing(host: String) -> String {
        "No SSH password is saved for \(host)."
    }

    static func sshPrivateKeyMissing(host: String) -> String {
        "No SSH private key is saved for \(host)."
    }

    static func sshAuthenticationFailed(host: String) -> String {
        "Authentication failed for \(host). Check its username and saved credential."
    }

    static func sshConnectionFailed(host: String, reason: String) -> String {
        "Could not connect to \(host): \(reason)"
    }

    private static let strings: [Key: String] = [
        .myRepos: "My Repositories",
        .starred: "Starred",
        .searchRepos: "Search Repositories",
        .viewUser: "View User",
        .chat: "Chat",
        .agent: "Agent",
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
        .sshAuthentication: "Authentication",
        .sshPasswordAuthentication: "Password",
        .sshKeyAuthentication: "SSH Key",
        .sshPublicKey: "Ed25519 Public Key",
        .copyPublicKey: "Copy Public Key",
        .copySSHSetupCommand: "Copy Setup Command",
        .generateSSHKey: "Generate SSH Key",
        .generateNewKey: "Replace Key",
        .sshPublicKeyHint: "For a Mac target, copy the setup command and paste it into Terminal. For other systems, add the public key as a new line in ~/.ssh/authorized_keys.",
        .sshHostEditorTitle: "SSH Host",
        .save: "Save",
        .sshHostKeyChanged: "The SSH host key changed. The connection was rejected to protect this computer.",
        .sshJumpHost: "Jump Host",
        .sshDirectConnection: "Direct Connection",
        .sshJumpHostHint: "Connect to this computer through another saved SSH host.",
        .sshJumpHostCycle: "The jump-host configuration contains a cycle.",
        .sshJumpRequiresKey: "Targets reached through a jump host use SSH key authentication.",
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
        .browse: "Browse…",
        .selectThisFolder: "Select This Folder",
        .directoryListingFailed: "Could not list the folders on this computer.",
        .repoLaunch: "RepoLaunch",
        .availableAgents: "Available Agents",
        .repoLaunchDescription: "Clone and prepare a repository on this Mac or an SSH computer.",
        .advancedOptions: "Advanced Options",
        .noFolderSelected: "Choose where to create the repository.",
        .deployRepository: "Deploy Repository",
        .repositoryURL: "Repository URL",
        .repositoryURLHint: "https://github.com/owner/repository.git",
        .gitReference: "Git Reference",
        .gitReferenceHint: "Optional branch, tag, or commit. Leave empty for the default branch.",
        .deploymentTarget: "Deployment Target",
        .destinationFolder: "Destination Folder",
        .destinationPath: "Destination Path",
        .destinationName: "Folder Name",
        .chooseParentFolder: "Choose Parent…",
        .linkExistingRepository: "Link Existing Repository",
        .deploymentCommands: "Environment & Verification",
        .setupCommands: "Setup Commands",
        .buildCommands: "Build Commands",
        .testCommands: "Test Commands",
        .commandsOptionalHint: "Optional shell commands run inside the deployed repository, in order. Their output and exit status are recorded.",
        .deploy: "Deploy",
        .deploying: "Deploying…",
        .repoLaunchRunning: "Running",
        .repoLaunchSucceeded: "Deployed",
        .repoLaunchFailed: "Failed",
        .repoLaunchCancelled: "Deployment cancelled.",
        .repoLaunchInterrupted: "Deployment was interrupted before completion.",
        .repoLaunchInvalidURL: "Enter a valid HTTPS, HTTP, SSH, or Git repository URL without embedded credentials.",
        .repoLaunchInvalidDestination: "Enter a valid destination path.",
        .repoLaunchLocalUnavailable: "Local deployment is only available on macOS.",
        .repoLaunchInvalidResult: "Deployment finished without valid repository verification output.",
        .repoLaunchTmuxUnavailable: "tmux is required on the deployment computer (including this Mac). Install tmux, e.g. with Homebrew, and try again.",
        .repoLaunchConnectionLost: "Connection to the deployment computer was lost.",
        .repoLaunchCommit: "Commit",
        .stagePreflight: "Preflight",
        .stageCheckout: "Checkout",
        .stageSetup: "Setup",
        .stageBuild: "Build",
        .stageTest: "Test",
        .stageVerify: "Verify",
        .coder: "Coder",
        .coderDescription: "Run interactive coding-CLI sessions (Kimi Code, Claude Code, or Codex) in tmux on a connected working tree.",
        .coderTool: "Tool",
        .coderWorkingCopy: "Working Copy",
        .coderSelectLocation: "Select a working copy",
        .coderNoLocations: "No connected repository locations. Connect a repository to a working tree first.",
        .coderNewSession: "New Session",
        .coderInitialPromptHint: "Initial task — leave empty to start an interactive session…",
        .coderStartSession: "Start Session",
        .coderSessions: "Sessions",
        .coderNoSessions: "No Coder sessions yet.",
        .coderKillSession: "Kill Session",
        .coderTurnFinished: "Turn finished",
        .coderCreateFailed: "Could Not Start Session",
        .coderToolUnavailable: "The selected coding CLI is not installed on the target computer.",
        .coderLocalUnavailable: "Local sessions are only available on macOS.",
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
