//
//  RepoListView.swift
//  GitAgent
//

import SwiftUI

/// A single repository row.
struct RepoRow: View {
    @Environment(AppSettings.self) private var settings
    let repo: Repo

    var body: some View {
        let uiSize = CGFloat(settings.uiFontSize)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: repo.isPrivate ? "lock.fill" : "book.closed")
                    .foregroundStyle(.secondary)
                    .font(.system(size: uiSize - 2))
                Text(repo.fullName)
                    .font(.system(size: uiSize + 1, weight: .semibold))
                    .lineLimit(1)
            }
            if let description = repo.description, !description.isEmpty {
                Text(description)
                    .font(.system(size: uiSize - 2))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 12) {
                if let language = repo.language {
                    Text(language)
                        .font(.system(size: uiSize - 4))
                        .foregroundStyle(.secondary)
                }
                Label("\(repo.stargazersCount)", systemImage: "star")
                    .font(.system(size: uiSize - 4))
                    .foregroundStyle(.secondary)
                if let updatedAt = repo.updatedAt {
                    Text(RelativeTime.short(updatedAt))
                        .font(.system(size: uiSize - 4))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// Tappable list of repositories.
struct RepoListView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(RepositoryLocationStore.self) private var locations
    let repos: [Repo]

    @State private var configuringRepo: Repo?

    var body: some View {
        List(repos) { repo in
            HStack(spacing: 10) {
                NavigationLink(value: repo) {
                    RepoRow(repo: repo)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                agentButton(for: repo)
            }
        }
        .sheet(item: $configuringRepo) { repo in
            RepositoryLocationsView(repo: repo)
        }
        .macTransparentScrollBackground()
        #if os(iOS)
        // Tighten the gap between the inline title and the first row.
        .contentMargins(.top, 8, for: .scrollContent)
        #endif
    }

    private func agentButton(for repo: Repo) -> some View {
        let isConnected = locations.hasConnectedLocation(for: repo.id)
        let color: Color = isConnected ? .green : .red
        let label = settings.tr(isConnected ? .agentConfigured : .agentNotConfigured)

        return Button {
            configuringRepo = repo
        } label: {
            Image(systemName: "terminal")
                .font(.system(size: CGFloat(settings.uiFontSize), weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.12), in: Circle())
                .accessibilityLabel(label)
        }
        .buttonStyle(.borderless)
        .help(label)
    }
}

/// Repository list wrapper that handles loading, error and empty states.
struct LoadingRepoListView: View {
    @Environment(GitHubAuthManager.self) private var auth
    @Environment(AppSettings.self) private var settings
    let loader: @Sendable (GitHubClient) async throws -> [Repo]

    @State private var repos: [Repo] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView(settings.tr(.loading))
            } else if let errorMessage {
                ContentUnavailableView {
                    Label(settings.tr(.loadFailed), systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button(settings.tr(.retry)) { Task { await load() } }
                }
            } else if repos.isEmpty {
                ContentUnavailableView(settings.tr(.noRepos), systemImage: "tray")
            } else {
                RepoListView(repos: repos)
                    .refreshable { await load() }
            }
        }
        .task { await load() }
    }

    private func load(afterCancel: Bool = false) async {
        guard let client = auth.client else { return }
        isLoading = true
        errorMessage = nil
        // The automatic load right after a view appears can fail transiently —
        // retry once automatically before showing an error.
        for attempt in 0...1 {
            do {
                repos = try await loader(client)
                break
            } catch GitHubError.unauthorized {
                auth.logout()
                return
            } catch {
                // On iOS the split-view push transition cancels the view's task
                // while the view (and its @State) survives — the request then
                // dies with a cancellation error. Retry in a fresh task that
                // isn't bound to the cancelled one.
                if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                    guard !afterCancel else { break }
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(300))
                        await load(afterCancel: true)
                    }
                    return
                }
                if attempt == 0, !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    continue
                }
                errorMessage = error.localizedDescription
            }
            break
        }
        isLoading = false
    }
}

/// Global repository search.
struct SearchReposView: View {
    @Environment(GitHubAuthManager.self) private var auth
    @Environment(AppSettings.self) private var settings
    @State private var keyword = ""
    @State private var repos: [Repo] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var hasSearched = false

    var body: some View {
        Group {
            if isSearching {
                ProgressView(settings.tr(.searching))
            } else if let errorMessage {
                ContentUnavailableView {
                    Label(settings.tr(.searchFailed), systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                }
            } else if hasSearched && repos.isEmpty {
                ContentUnavailableView(settings.tr(.noSearchResults), systemImage: "magnifyingglass")
            } else if repos.isEmpty {
                ContentUnavailableView(settings.tr(.searchReposHint), systemImage: "magnifyingglass")
            } else {
                RepoListView(repos: repos)
            }
        }
        .navigationTitle(settings.tr(.searchRepos))
        .searchable(text: $keyword, prompt: settings.tr(.searchKeywordPrompt))
        .onSubmit(of: .search) { Task { await search() } }
    }

    private func search() async {
        guard let client = auth.client, !keyword.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching = true
        errorMessage = nil
        do {
            repos = try await client.searchRepos(keyword: keyword)
        } catch GitHubError.unauthorized {
            auth.logout()
            return
        } catch {
            errorMessage = error.localizedDescription
        }
        hasSearched = true
        isSearching = false
    }
}

/// Public repositories of an arbitrary GitHub user.
struct UserReposView: View {
    @Environment(AppSettings.self) private var settings
    @State private var username = ""
    @State private var submittedUsername: String?

    var body: some View {
        Group {
            if let submittedUsername {
                LoadingRepoListView { client in
                    try await client.userRepos(username: submittedUsername)
                }
                .id(submittedUsername)
            } else {
                ContentUnavailableView(settings.tr(.searchUserHint), systemImage: "person")
            }
        }
        .navigationTitle(settings.tr(.viewUser))
        .searchable(text: $username, prompt: settings.tr(.usernamePrompt))
        .onSubmit(of: .search) {
            let name = username.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { submittedUsername = name }
        }
    }
}

#Preview {
    NavigationStack {
        RepoListView(repos: [])
            .environment(GitHubAuthManager())
            .environment(AppSettings())
            .environment(RepositoryLocationStore())
            .environment(SSHHostStore())
            .environment(TerminalLaunchCoordinator())
    }
}
