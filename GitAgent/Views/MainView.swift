//
//  MainView.swift
//  GitAgent
//

import SwiftUI

enum SidebarItem: CaseIterable, Identifiable, Hashable {
    case mine, search, user

    var id: Self { self }

    var titleKey: L10n.Key {
        switch self {
        case .mine: return .myRepos
        case .search: return .searchRepos
        case .user: return .viewUser
        }
    }

    var icon: String {
        switch self {
        case .mine: return "books.vertical"
        case .search: return "magnifyingglass"
        case .user: return "person"
        }
    }
}

struct MainView: View {
    @Environment(GitHubAuthManager.self) private var auth
    @Environment(AppSettings.self) private var settings
    @State private var selection: SidebarItem? = .mine
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                if case .loggedIn(let user) = auth.state {
                    Section {
                        HStack(spacing: 10) {
                            AsyncImage(url: user.avatarURL) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Image(systemName: "person.crop.circle.fill")
                                    .resizable()
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 36, height: 36)
                            .clipShape(Circle())

                            VStack(alignment: .leading) {
                                Text(user.name ?? user.login).font(.headline)
                                Text("@\(user.login)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section {
                    ForEach(SidebarItem.allCases) { item in
                        Label(settings.tr(item.titleKey), systemImage: item.icon)
                            .tag(item)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        auth.logout()
                    } label: {
                        Label(settings.tr(.logout), systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("GitAgent")
        } detail: {
            NavigationStack(path: $navigationPath) {
                detailView
                    .navigationDestination(for: Repo.self) { repo in
                        RepoDetailView(repo: repo, navigationPath: $navigationPath)
                    }
                    .navigationDestination(for: RepoLinkRef.self) { ref in
                        LinkedRepoView(ref: ref, navigationPath: $navigationPath)
                    }
                    .navigationDestination(for: RepoFileRef.self) { ref in
                        if ref.isMarkdown {
                            MarkdownFileView(ref: ref, navigationPath: $navigationPath)
                        } else {
                            TextFileView(ref: ref)
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection ?? .mine {
        case .mine:
            LoadingRepoListView { client in
                try await client.myRepos()
            }
            .navigationTitle(settings.tr(.myRepos))
        case .search:
            SearchReposView()
        case .user:
            UserReposView()
        }
    }
}

#Preview {
    MainView()
        .environment(GitHubAuthManager())
        .environment(AppSettings())
}
