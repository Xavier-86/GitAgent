//
//  MainView.swift
//  GitAgent
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

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
    #if os(macOS)
    @Environment(WorkspaceStore.self) private var workspace
    #endif
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    @State private var selection: SidebarItem? = .mine
    @State private var navigationPath = NavigationPath()
    #if os(macOS)
    @State private var splitVisibility: NavigationSplitViewVisibility = .detailOnly
    #else
    @State private var splitVisibility: NavigationSplitViewVisibility = .automatic
    #endif
    @State private var showSettings = false
    @State private var showLogoutConfirmation = false
    @State private var showProfile = false
    #if os(macOS)
    @State private var workspaceToolbarWidth: CGFloat = 660
    #endif

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
        #if os(macOS)
        .toolbar {
            workspaceToolbar
        }
        .background {
            NewPageTitlebarAccessory {
                workspace.openNewPage()
            }
        }
        #endif
    }

    #if os(macOS)
    @ToolbarContentBuilder
    private var workspaceToolbar: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            HStack(spacing: 8) {
                Button {
                    withAnimation {
                        splitVisibility = splitVisibility == .detailOnly ? .automatic : .detailOnly
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                        .frame(width: 28, height: 28, alignment: .center)
                }
                .buttonStyle(.plain)
                .offset(x: 4)

                Button {
                    workspace.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 28, height: 28, alignment: .center)
                }
                .buttonStyle(.plain)
                .disabled(!workspace.canGoBack)
                .help(settings.tr(.back))

                WorkspaceTabBar()
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .layoutPriority(1)
            }
            .frame(height: 34, alignment: .center)
            .frame(width: max(100, workspaceToolbarWidth - 180), alignment: .leading)
        }

    }
    #endif

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
                Group {
                    #if os(macOS)
                    WorkspacePageHost()
                    #else
                    detailView(for: selection ?? .mine)
                    #endif
                }
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
            #if os(macOS)
            .background {
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { workspaceToolbarWidth = geometry.size.width }
                        .onChange(of: geometry.size.width) { _, width in
                            workspaceToolbarWidth = width
                        }
                }
            }
            #endif
        }
        // Environment, not a stored property: pushed detail pages
        // (CoderView, CoderTerminalView, …) reach the same binding through
        // `sidebarToggleButton()`. It must live on the split view itself —
        // a value set inside the detail column reaches the column's root
        // page but does NOT propagate to pushed pages on macOS.
        .environment(\.sidebarVisibility, $splitVisibility)
        #if os(macOS)
        .onChange(of: selection) { _, _ in
            guard let selection else { return }
            openSidebarPage(selection)
        }
        .onChange(of: workspace.selectedID) { _, _ in
            // A repository may have been pushed above this root stack when a
            // global tab is opened. Pop it before showing the newly selected
            // page, otherwise the old detail view remains visually on top.
            navigationPath = NavigationPath()
        }
        #endif
    }

    // MARK: - Shared sidebar pieces

    private var settingsButton: some View {
        Button {
            #if os(macOS)
            workspace.showSettings()
            #else
            showSettings = true
            #endif
        } label: {
            Image(systemName: "gearshape")
        }
    }

    @ViewBuilder
    private var profileSection: some View {
        if case .loggedIn(let user) = auth.state {
            Section {
                Button {
                    #if os(macOS)
                    workspace.showProfile()
                    #else
                    showProfile = true
                    #endif
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

                #if os(macOS)
                Button {
                    workspace.showSettings()
                } label: {
                    Label(settings.tr(.settings), systemImage: "gearshape")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                #endif
            }
            #if os(iOS)
            .sheet(isPresented: $showProfile) {
                UserProfileView(user: user)
            }
            #endif
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

    #if os(macOS)
    /// Sidebar navigation updates the selected page and records its previous
    /// destination in that page's browser-style back history.
    private func openSidebarPage(_ item: SidebarItem) {
        switch item {
        case .mine: workspace.showMyRepositories()
        case .starred: workspace.showStarred()
        case .chat: workspace.showChat()
        case .agent: workspace.showAgent()
        case .terminal: workspace.showTerminal()
        }
    }
    #endif

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
        .environment(WorkspaceStore())
}

// MARK: - Sidebar toggle

/// Carries the split view's column-visibility binding down the detail
/// stack, so any page — including pushed ones — can install the toggle.
private struct SidebarVisibilityKey: EnvironmentKey {
    static let defaultValue: Binding<NavigationSplitViewVisibility>? = nil
}

private struct WorkspacePageKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var sidebarVisibility: Binding<NavigationSplitViewVisibility>? {
        get { self[SidebarVisibilityKey.self] }
        set { self[SidebarVisibilityKey.self] = newValue }
    }
    var isWorkspacePage: Bool {
        get { self[WorkspacePageKey.self] }
        set { self[WorkspacePageKey.self] = newValue }
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
    @Environment(\.isWorkspacePage) private var isWorkspacePage

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(macOS)
        if isWorkspacePage {
            content
                .toolbar(removing: .sidebarToggle)
                .toolbar(removing: .title)
        } else {
            content
                .toolbar(removing: .sidebarToggle)
        }
        #else
        content
            .toolbar(removing: .sidebarToggle)
            .toolbar {
                if let visibility, !isWorkspacePage {
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
        #endif
    }
}

extension View {
    func sidebarToggleButton() -> some View {
        modifier(SidebarToggleButton())
    }
}

#if os(macOS)
/// Installs the new-page button as a window-level trailing titlebar
/// accessory. Unlike a SwiftUI toolbar item, its position is independent of
/// NavigationSplitView's changing sidebar and detail toolbar regions.
private struct NewPageTitlebarAccessory: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> TitlebarAccessoryInstallerView {
        let view = TitlebarAccessoryInstallerView()
        view.action = action
        return view
    }

    func updateNSView(_ nsView: TitlebarAccessoryInstallerView, context: Context) {
        nsView.action = action
    }

    static func dismantleNSView(_ nsView: TitlebarAccessoryInstallerView, coordinator: ()) {
        nsView.uninstall()
    }
}

private final class TitlebarAccessoryInstallerView: NSView {
    var action: (() -> Void)?

    private weak var installedWindow: NSWindow?
    private var accessoryController: NSTitlebarAccessoryViewController?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window !== installedWindow else { return }
        uninstall()
        if let window {
            install(in: window)
        }
    }

    func uninstall() {
        if let installedWindow,
           let accessoryController,
           let index = installedWindow.titlebarAccessoryViewControllers.firstIndex(
               where: { $0 === accessoryController }
           ) {
            installedWindow.removeTitlebarAccessoryViewController(at: index)
        }
        accessoryController = nil
        installedWindow = nil
    }

    private func install(in window: NSWindow) {
        let button = NSButton()
        button.image = NSImage(
            systemSymbolName: "plus.circle.fill",
            accessibilityDescription: L10n.resolveCurrent(.newPage)
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 21, weight: .semibold)
        )
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.focusRingType = .none
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = L10n.resolveCurrent(.newPage)
        button.target = self
        button.action = #selector(openNewPage)
        button.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 48, height: 28))
        container.addSubview(button)
        NSLayoutConstraint.activate([
            button.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            button.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: 28),
            button.heightAnchor.constraint(equalToConstant: 28),
        ])

        let controller = NSTitlebarAccessoryViewController()
        controller.layoutAttribute = .right
        controller.view = container
        accessoryController = controller
        installedWindow = window
        window.addTitlebarAccessoryViewController(controller)
    }

    @objc private func openNewPage() {
        action?()
    }
}
#endif
