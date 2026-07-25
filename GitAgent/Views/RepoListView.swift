//
//  RepoListView.swift
//  GitAgent
//

import SwiftUI

/// A single repository row.
struct RepoRow: View {
    let repo: Repo

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: repo.isPrivate ? "lock.fill" : "book.closed")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                Text(repo.fullName)
                    .font(.headline)
                    .lineLimit(1)
            }
            if let description = repo.description, !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 12) {
                if let language = repo.language {
                    Text(language)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Label("\(repo.stargazersCount)", systemImage: "star")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let updatedAt = repo.updatedAt {
                    Text(Self.relativeShort(updatedAt))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// Single-unit relative time ("3m ago", "2d ago") — only the largest unit.
    private static let relativeFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .hour, .day, .weekOfMonth, .month, .year]
        formatter.maximumUnitCount = 1
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private static func relativeShort(_ date: Date) -> String {
        let interval = max(0, -date.timeIntervalSinceNow)
        guard interval >= 60 else { return "just now" }
        let unit = Self.relativeFormatter.string(from: interval) ?? ""
        return "\(unit) ago"
    }
}

/// Tappable list of repositories.
struct RepoListView: View {
    let repos: [Repo]

    var body: some View {
        List(repos) { repo in
            NavigationLink(value: repo) {
                RepoRow(repo: repo)
            }
        }
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

    private func load() async {
        guard let client = auth.client else { return }
        isLoading = true
        errorMessage = nil
        do {
            repos = try await loader(client)
        } catch GitHubError.unauthorized {
            auth.logout()
            return
        } catch {
            errorMessage = error.localizedDescription
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
    }
}
