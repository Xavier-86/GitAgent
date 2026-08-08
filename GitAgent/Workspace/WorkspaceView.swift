//
//  WorkspaceView.swift
//  GitAgent
//

import SwiftUI

/// Browser-like tab strip placed in the macOS window toolbar.
struct WorkspaceTabBar: View {
    @Environment(WorkspaceStore.self) private var workspace
    private let trailingAnchor = "workspace-page-strip-trailing-edge"

    var body: some View {
        pageStrip
    }

    private var pageStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(workspace.pages) { page in
                        Button {
                            workspace.selectedID = page.id
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: page.icon)
                                Text(workspace.title(for: page)).lineLimit(1)
                                Button {
                                    workspace.close(page.id)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.caption.weight(.semibold))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Close \(workspace.title(for: page))")
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(
                                workspace.selectedID == page.id ? Color.accentColor.opacity(0.18) : .clear,
                                in: RoundedRectangle(cornerRadius: 7)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Color.clear
                        .frame(width: 1, height: 1)
                        .id(trailingAnchor)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .onChange(of: workspace.pages.count) { oldCount, newCount in
                guard newCount > oldCount else { return }
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(trailingAnchor, anchor: .trailing)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

}

/// Keeps every open page mounted and only changes which one is visible.
/// Stateful pages such as terminals and web views therefore survive tab
/// switches; replacing or closing a page still tears its old content down.
struct WorkspacePageHost: View {
    @Environment(WorkspaceStore.self) private var workspace
    @Environment(GitHubAuthManager.self) private var auth

    var body: some View {
        ZStack {
            Color.clear

            ForEach(workspace.pages) { page in
                pageView(page)
                    // The page ID remains stable while normal navigation
                    // changes its content. The full enum value changes in
                    // that case so SwiftUI discards only the replaced page.
                    .id(page)
                    .environment(\.isWorkspacePage, true)
                    .opacity(workspace.selectedID == page.id ? 1 : 0)
                    .allowsHitTesting(workspace.selectedID == page.id)
                    .accessibilityHidden(workspace.selectedID != page.id)
                    .zIndex(workspace.selectedID == page.id ? 1 : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // The browser-like tab itself is the page title. Suppress the
        // navigation stack's duplicate title in the window toolbar.
        .navigationTitle("")
        .toolbar(removing: .title)
    }

    @ViewBuilder
    private func pageView(_ page: WorkspaceStore.Page) -> some View {
        switch page {
        case .newPage:
            NewWorkspacePageView()
        case .myRepositories:
            LoadingRepoListView { client in try await client.myRepos() }
                .navigationTitle("My Repositories")
        case .starred:
            LoadingRepoListView { client in try await client.starredRepos() }
                .navigationTitle("Starred")
        case .chat(let id):
            ChatView(sessionID: id)
        case .agent:
            AgentView()
        case .coder:
            CoderView()
        case .coderTerminal(_, let recordID):
            CoderTerminalView(recordID: recordID)
        case .terminal:
            SSHView()
        case .profile:
            if case .loggedIn(let user) = auth.state {
                UserProfileView(user: user)
            } else {
                Color.clear
            }
        case .settings:
            SettingsView()
        case .repository(_, let repo):
            RepoDetailView(repo: repo)
        case .localRepository(_, let repo, let location):
            #if os(macOS)
            LocalRepositoryView(repo: repo, location: location)
            #else
            ContentUnavailableView("Local files are available on Mac", systemImage: "externaldrive")
            #endif
        }
    }
}

/// The first view of a newly created browser page mirrors every primary
/// sidebar destination, while keeping the choices visual and direct.
private struct NewWorkspacePageView: View {
    @Environment(WorkspaceStore.self) private var workspace
    @Environment(AppSettings.self) private var settings

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(.secondary)
                Text("New Page")
                    .font(.title2.weight(.semibold))
                Text("Choose where to start working.")
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 14)], spacing: 14) {
                    launchButton(
                        title: "Repositories",
                        subtitle: "Browse your GitHub repositories",
                        icon: "books.vertical",
                        color: .blue,
                        action: workspace.showMyRepositories
                    )
                    launchButton(
                        title: "Starred",
                        subtitle: "See repositories you have starred",
                        icon: "star",
                        color: .yellow,
                        action: workspace.showStarred
                    )
                    launchButton(
                        title: "Chat",
                        subtitle: "Start a focused AI conversation",
                        icon: "bubble.left.and.bubble.right",
                        color: .teal,
                        action: workspace.showChat
                    )
                    launchButton(
                        title: "Agent",
                        subtitle: "Launch repository tools and coding sessions",
                        icon: "brain.head.profile",
                        color: .purple,
                        action: workspace.showAgent
                    )
                    launchButton(
                        title: "Terminal",
                        subtitle: "Connect to a local or SSH shell",
                        icon: "terminal",
                        color: .orange,
                        action: workspace.showTerminal
                    )
                    launchButton(
                        title: settings.tr(.profile),
                        subtitle: settings.tr(.profileDescription),
                        icon: "person.crop.circle",
                        color: .indigo,
                        action: workspace.showProfile
                    )
                    launchButton(
                        title: settings.tr(.settings),
                        subtitle: settings.tr(.settingsDescription),
                        icon: "gearshape",
                        color: .gray,
                        action: workspace.showSettings
                    )
                }
                .frame(maxWidth: 760)
            }
            .frame(maxWidth: .infinity)
            .padding(24)
        }
        .navigationTitle("New Page")
    }

    private func launchButton(title: String, subtitle: String, icon: String,
                              color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                    .frame(width: 42, height: 42)
                    .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 11))
                Text(title).font(.headline)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
            .padding(16)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}
