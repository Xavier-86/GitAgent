//
//  MainView.swift
//  GitAgent
//

import SwiftUI

enum SidebarItem: CaseIterable, Identifiable, Hashable {
    case mine, starred, chat, agent, terminal

    var id: Self { self }

    var titleKey: L10n.Key {
        switch self {
        case .mine: return .myRepos
        case .starred: return .starred
        case .chat: return .chat
        case .agent: return .agent
        case .terminal: return .terminal
        }
    }

    var icon: String {
        switch self {
        case .mine: return "books.vertical"
        case .starred: return "star"
        case .chat: return "bubble.left.and.bubble.right"
        case .agent: return "brain.head.profile"
        case .terminal: return "terminal"
        }
    }
}

struct MainView: View {
    @Environment(GitHubAuthManager.self) private var auth
    @Environment(AppSettings.self) private var settings
    @Environment(TerminalLaunchCoordinator.self) private var terminalLauncher
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    @State private var selection: SidebarItem? = .mine
    @State private var navigationPath = NavigationPath()
    @State private var splitVisibility: NavigationSplitViewVisibility = .automatic
    @State private var showSettings = false
    @State private var showLogoutConfirmation = false
    @State private var showProfile = false

    var body: some View {
        Group {
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
        .onChange(of: terminalLauncher.request?.id, initial: true) { _, requestID in
            guard requestID != nil else { return }
            showTerminal()
        }
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
        NavigationSplitView(columnVisibility: $splitVisibility) {
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
            .macTransparentScrollBackground()
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
            // The detail column owns the single, fixed sidebar toggle.
            .toolbar(removing: .sidebarToggle)
        } detail: {
            NavigationStack(path: $navigationPath) {
                detailView(for: selection ?? .mine)
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .iOSHidesBackButton()
                    .sidebarToggleButton()
                    .navigationDestination(for: Repo.self) { repo in
                        RepoDetailView(repo: repo)
                            .sidebarToggleButton()
                    }
            }
        }
        // Environment, not a stored property: pushed detail pages
        // (CoderView, CoderTerminalView, …) reach the same binding through
        // `sidebarToggleButton()`. It must live on the split view itself —
        // a value set inside the detail column reaches the column's root
        // page but does NOT propagate to pushed pages on macOS.
        .environment(\.sidebarVisibility, $splitVisibility)
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
                // Plain style: the default macOS button style draws a whitish
                // capsule over the sidebar material.
                .buttonStyle(.plain)
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

    private func showTerminal() {
        navigationPath = NavigationPath()
        #if os(iOS)
        if horizontalSizeClass == .compact {
            navigationPath.append(SidebarItem.terminal)
        } else {
            selection = .terminal
        }
        #else
        selection = .terminal
        #endif
    }

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
        case .chat:
            ChatView()
        case .agent:
            AgentView()
        case .terminal:
            SSHView()
        }
    }
}

#Preview {
    MainView()
        .environment(GitHubAuthManager())
        .environment(AppSettings())
        .environment(TerminalLaunchCoordinator())
        .environment(RepoLaunchStore())
        .environment(RepositoryLocationStore())
        .environment(SSHHostStore())
}

// MARK: - Sidebar toggle

/// Carries the split view's column-visibility binding down the detail
/// stack, so any page — including pushed ones — can install the toggle.
private struct SidebarVisibilityKey: EnvironmentKey {
    static let defaultValue: Binding<NavigationSplitViewVisibility>? = nil
}

extension EnvironmentValues {
    var sidebarVisibility: Binding<NavigationSplitViewVisibility>? {
        get { self[SidebarVisibilityKey.self] }
        set { self[SidebarVisibilityKey.self] = newValue }
    }
}

/// The one fixed sidebar toggle. The system's variant changes icon and
/// placement with platform and split state, so it is removed everywhere
/// and replaced with this button. Toolbar items do not propagate to pushed
/// pages in the detail stack, so every page that can appear there applies
/// this modifier itself; pages outside a split view get a nil binding and
/// render no button.
private struct SidebarToggleButton: ViewModifier {
    @Environment(\.sidebarVisibility) private var visibility

    func body(content: Content) -> some View {
        content
            .toolbar(removing: .sidebarToggle)
            .toolbar {
                if let visibility {
                    ToolbarItem(placement: .navigation) {
                        Button {
                            withAnimation {
                                visibility.wrappedValue =
                                    visibility.wrappedValue == .detailOnly ? .automatic : .detailOnly
                            }
                        } label: {
                            Image(systemName: "sidebar.left")
                        }
                    }
                }
            }
    }
}

extension View {
    func sidebarToggleButton() -> some View {
        modifier(SidebarToggleButton())
    }
}
