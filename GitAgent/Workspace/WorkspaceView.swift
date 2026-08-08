//
//  WorkspaceView.swift
//  GitAgent
//

import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Browser-like tab strip placed in the macOS window toolbar.
struct WorkspaceTabBar: View {
    @Environment(WorkspaceStore.self) private var workspace
    @Environment(AppSettings.self) private var settings
    private let trailingAnchor = "workspace-page-strip-trailing-edge"

    private var tabFontSize: CGFloat {
        CGFloat(max(11, settings.uiFontSize - 2))
    }

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
                                        .frame(width: 18, height: 18)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(
                                    L10n.closePage(title: workspace.title(for: page))
                                )
                            }
                            .font(.system(size: tabFontSize))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(
                                workspace.selectedID == page.id ? Color.accentColor.opacity(0.18) : .clear,
                                in: RoundedRectangle(cornerRadius: 7)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 7))
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
    @Environment(AppSettings.self) private var settings

    var body: some View {
        ZStack {
            Color.clear

            #if os(macOS)
            if workspace.pages.isEmpty {
                EmptyWorkspacePlaceholder()
            }
            #endif

            ForEach(workspace.pages) { page in
                hostedPage(page)
                    // The page ID remains stable while normal navigation
                    // changes its content. The full enum value changes in
                    // that case so SwiftUI discards only the replaced page.
                    .id(page)
                    .environment(\.isWorkspacePage, true)
                    .environment(\.workspacePageID, page.id)
                    .opacity(workspace.selectedID == page.id ? 1 : 0)
                    .allowsHitTesting(workspace.selectedID == page.id)
                    .accessibilityHidden(workspace.selectedID != page.id)
                    .zIndex(workspace.selectedID == page.id ? 1 : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        #if os(macOS)
        // The browser-like tab itself is the page title. Suppress the
        // navigation stack's duplicate title in the window toolbar.
        .navigationTitle("")
        .toolbar(removing: .title)
        #endif
    }

    @ViewBuilder
    private func hostedPage(_ page: WorkspaceStore.Page) -> some View {
        #if os(iOS)
        NavigationStack {
            pageView(page)
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: Repo.self) { repo in
                    RepoDetailView(repo: repo)
                        .navigationBarTitleDisplayMode(.inline)
                        .iOSHidesBackButton()
                }
        }
        #else
        pageView(page)
        #endif
    }

    @ViewBuilder
    private func pageView(_ page: WorkspaceStore.Page) -> some View {
        switch page {
        case .newPage:
            NewWorkspacePageView()
        case .myRepositories:
            LoadingRepoListView { client in try await client.myRepos() }
                .navigationTitle(settings.tr(.myRepos))
        case .starred:
            LoadingRepoListView { client in try await client.starredRepos() }
                .navigationTitle(settings.tr(.starred))
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
            ContentUnavailableView(
                settings.tr(.localFilesAvailableOnMac),
                systemImage: "externaldrive"
            )
            #endif
        case .remoteRepository(_, let repo, let location):
            RemoteRepositoryView(repo: repo, location: location)
        }
    }
}

#if os(macOS)
private struct EmptyWorkspacePlaceholder: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApplication.shared.applicationIconImage ?? NSImage())
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)

            Text("GitAgent")
                .font(.title2.weight(.semibold))

            Text(settings.tr(.appTagline))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}
#endif

#if os(iOS)
struct MobileWorkspacePageSwitcher: View {
    @Environment(WorkspaceStore.self) private var workspace
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(workspace.pages) { page in
                        pageCard(page)
                    }
                }
                .padding(12)
            }
            .navigationTitle(settings.tr(.pages))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(settings.tr(.done)) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        workspace.openNewPage()
                        dismiss()
                        MobileWorkspacePreview.captureAfterTransition(in: workspace)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(settings.tr(.newPage))
                }
            }
        }
    }

    private func pageCard(_ page: WorkspaceStore.Page) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                workspace.selectedID = page.id
                dismiss()
                MobileWorkspacePreview.captureAfterTransition(in: workspace)
            } label: {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Image(systemName: page.icon)
                            .foregroundStyle(.secondary)
                        Text(workspace.title(for: page))
                            .font(.headline)
                            .lineLimit(1)
                        Spacer(minLength: 28)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 42)

                    Divider()
                    pagePreview(page)
                }
                .frame(maxWidth: .infinity, minHeight: 160, maxHeight: 160)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            workspace.selectedID == page.id ? Color.accentColor : .secondary.opacity(0.2),
                            lineWidth: workspace.selectedID == page.id ? 2 : 1
                        )
                }
                .contentShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)

            Button {
                workspace.close(page.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.body)
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.closePage(title: workspace.title(for: page)))
            .padding(4)
        }
    }

    @ViewBuilder
    private func pagePreview(_ page: WorkspaceStore.Page) -> some View {
        if let data = workspace.pagePreviewData[page.id],
           let preview = UIImage(data: data) {
            Image(uiImage: preview)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .allowsHitTesting(false)
        } else {
            Image(systemName: page.icon)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background.opacity(0.35))
        }
    }
}

@MainActor
enum MobileWorkspacePreview {
    static func captureSelected(in workspace: WorkspaceStore) {
        guard let pageID = workspace.selectedID,
              let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: \.isKeyWindow),
              window.bounds.width > 0 else { return }

        let targetWidth: CGFloat = 240
        let scale = targetWidth / window.bounds.width
        let targetSize = CGSize(width: targetWidth, height: window.bounds.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let image = renderer.image { _ in
            window.drawHierarchy(
                in: CGRect(origin: .zero, size: targetSize),
                afterScreenUpdates: true
            )
        }
        guard let data = image.jpegData(compressionQuality: 0.72) else { return }
        workspace.updatePagePreview(data, for: pageID)
    }

    static func captureAfterTransition(in workspace: WorkspaceStore) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            captureSelected(in: workspace)
        }
    }
}
#endif

/// The first view of a newly created browser page mirrors every primary
/// sidebar destination, while keeping the choices visual and direct.
private struct NewWorkspacePageView: View {
    @Environment(WorkspaceStore.self) private var workspace
    @Environment(AppSettings.self) private var settings

    var body: some View {
        ScrollView {
            VStack(spacing: layoutSpacing) {
                #if os(macOS)
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(.secondary)
                Text(settings.tr(.newPage))
                    .font(.title2.weight(.semibold))
                #endif

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 230), spacing: layoutSpacing)],
                    spacing: layoutSpacing
                ) {
                    launchButton(
                        title: settings.tr(.repositories),
                        subtitle: settings.tr(.pageRepositoriesDescription),
                        icon: "books.vertical",
                        color: .blue,
                        action: workspace.showMyRepositories
                    )
                    launchButton(
                        title: settings.tr(.starred),
                        subtitle: settings.tr(.pageStarredDescription),
                        icon: "star",
                        color: .yellow,
                        action: workspace.showStarred
                    )
                    launchButton(
                        title: settings.tr(.chat),
                        subtitle: settings.tr(.pageChatDescription),
                        icon: "bubble.left.and.bubble.right",
                        color: .teal,
                        action: workspace.showChat
                    )
                    launchButton(
                        title: settings.tr(.agent),
                        subtitle: settings.tr(.pageAgentDescription),
                        icon: "brain.head.profile",
                        color: .purple,
                        action: workspace.showAgent
                    )
                    launchButton(
                        title: settings.tr(.terminal),
                        subtitle: settings.tr(.pageTerminalDescription),
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
                }
                .frame(maxWidth: 760)
            }
            .frame(maxWidth: .infinity)
            #if os(iOS)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            #else
            .padding(24)
            #endif
        }
        .navigationTitle(settings.tr(.newPage))
    }

    private var layoutSpacing: CGFloat {
        #if os(iOS)
        10
        #else
        14
        #endif
    }

    private func launchButton(title: String, subtitle: String, icon: String,
                              color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            #if os(iOS)
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(color)
                    .frame(width: 38, height: 38)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: CGFloat(settings.uiFontSize), weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: CGFloat(max(12, settings.uiFontSize - 2))))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            // Keep the entire visible row clickable, including empty space.
            .contentShape(RoundedRectangle(cornerRadius: 13))
            .background(.background, in: RoundedRectangle(cornerRadius: 13))
            .overlay {
                RoundedRectangle(cornerRadius: 13)
                    .stroke(.primary.opacity(0.1), lineWidth: 1)
            }
            #else
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                    .frame(width: 42, height: 42)
                    .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 11))

                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.headline)
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
            .padding(16)
            .contentShape(RoundedRectangle(cornerRadius: 16))
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
            #endif
        }
        .buttonStyle(.plain)
    }
}
