//
//  MainView.swift
//  GitAgent
//

import SwiftUI

enum SidebarItem: CaseIterable, Identifiable, Hashable {
    case mine, starred, search, user, chat

    var id: Self { self }

    var titleKey: L10n.Key {
        switch self {
        case .mine: return .myRepos
        case .starred: return .starred
        case .search: return .searchRepos
        case .user: return .viewUser
        case .chat: return .chat
        }
    }

    var icon: String {
        switch self {
        case .mine: return "books.vertical"
        case .starred: return "star"
        case .search: return "magnifyingglass"
        case .user: return "person"
        case .chat: return "bubble.left.and.bubble.right"
        }
    }
}

struct MainView: View {
    @Environment(GitHubAuthManager.self) private var auth
    @Environment(AppSettings.self) private var settings
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    @State private var selection: SidebarItem? = .mine
    @State private var navigationPath = NavigationPath()
    @State private var showSettings = false
    @State private var showLogoutConfirmation = false
    @State private var showProfile = false

    var body: some View {
        #if os(iOS)
        // iPhone: a single NavigationStack — the menu is the root and pages
        // push on top, so the system edge swipe pops exactly one level. A
        // collapsed NavigationSplitView runs TWO competing gesture systems
        // (detail-stack pop + sidebar reveal) and pops twice per swipe.
        if horizontalSizeClass == .compact {
            compactNavigation
        } else {
            splitNavigation
        }
        #else
        splitNavigation
        #endif
    }

    // MARK: - iPhone (compact): single stack

    #if os(iOS)
    private var compactNavigation: some View {
        NavigationStack(path: $navigationPath) {
            List {
                profileSection
                Section {
                    ForEach(SidebarItem.allCases) { item in
                        NavigationLink(value: item) {
                            Label(settings.tr(item.titleKey), systemImage: item.icon)
                        }
                    }
                }
                signOutSection
            }
            .navigationTitle("GitAgent")
            .navigationBarTitleDisplayMode(.inline)
            // Tighten the gap between the nav bar and the profile card.
            .contentMargins(.top, 8, for: .scrollContent)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    settingsButton
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .alert(settings.tr(.logout), isPresented: $showLogoutConfirmation) {
                Button(settings.tr(.logout), role: .destructive) { auth.logout() }
                Button(settings.tr(.cancel), role: .cancel) {}
            } message: {
                Text(settings.tr(.logoutConfirmMessage))
            }
            .navigationDestination(for: SidebarItem.self) { item in
                detailView(for: item)
                    .navigationBarTitleDisplayMode(.inline)
                    .iOSHidesBackButton()
            }
            .navigationDestination(for: Repo.self) { repo in
                RepoDetailView(repo: repo)
            }
        }
    }
    #endif

    // MARK: - iPad / macOS: split view

    private var splitNavigation: some View {
        NavigationSplitView {
            List(selection: $selection) {
                profileSection
                Section {
                    ForEach(SidebarItem.allCases) { item in
                        Label(settings.tr(item.titleKey), systemImage: item.icon)
                            .tag(item)
                    }
                }
                signOutSection
            }
            .navigationTitle("GitAgent")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .contentMargins(.top, 8, for: .scrollContent)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    settingsButton
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            #endif
            .alert(settings.tr(.logout), isPresented: $showLogoutConfirmation) {
                Button(settings.tr(.logout), role: .destructive) { auth.logout() }
                Button(settings.tr(.cancel), role: .cancel) {}
            } message: {
                Text(settings.tr(.logoutConfirmMessage))
            }
        } detail: {
            NavigationStack(path: $navigationPath) {
                detailView(for: selection ?? .mine)
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .iOSHidesBackButton()
                    .navigationDestination(for: Repo.self) { repo in
                        RepoDetailView(repo: repo)
                    }
            }
        }
    }

    // MARK: - Shared sidebar pieces

    private var settingsButton: some View {
        Button {
            showSettings = true
        } label: {
            Image(systemName: "gearshape")
        }
    }

    @ViewBuilder
    private var profileSection: some View {
        if case .loggedIn(let user) = auth.state {
            Section {
                Button {
                    showProfile = true
                } label: {
                    HStack(spacing: 10) {
                        AvatarView(url: user.avatarURL, size: 36)

                        VStack(alignment: .leading) {
                            Text(user.name ?? user.login)
                                .font(.system(size: CGFloat(settings.uiFontSize) + 1, weight: .semibold))
                            Text("@\(user.login)")
                                .font(.system(size: CGFloat(settings.uiFontSize) - 4))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
            .sheet(isPresented: $showProfile) {
                UserProfileView(user: user)
            }
        }
    }

    private var signOutSection: some View {
        Section {
            Button(role: .destructive) {
                showLogoutConfirmation = true
            } label: {
                Label(settings.tr(.logout), systemImage: "rectangle.portrait.and.arrow.right")
            }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private func detailView(for item: SidebarItem) -> some View {
        switch item {
        case .mine:
            LoadingRepoListView { client in
                try await client.myRepos()
            }
            .navigationTitle(settings.tr(.myRepos))
        case .starred:
            LoadingRepoListView { client in
                try await client.starredRepos()
            }
            .navigationTitle(settings.tr(.starred))
        case .search:
            SearchReposView()
        case .user:
            UserReposView()
        case .chat:
            ChatView()
        }
    }
}

#Preview {
    MainView()
        .environment(GitHubAuthManager())
        .environment(AppSettings())
}
