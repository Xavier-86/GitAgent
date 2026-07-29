//
//  RepoDetailView.swift
//  GitAgent
//

import SwiftUI

/// Builds the raw.githubusercontent.com base URL used to resolve relative image paths in Markdown.
func rawBaseURL(owner: String, repo: String, branch: String, directory: String = "") -> URL? {
    var url = URL(string: "https://raw.githubusercontent.com")!
        .appending(path: owner)
        .appending(path: repo)
        .appending(path: branch)
    if !directory.isEmpty {
        url = url.appending(path: directory)
    }
    return URL(string: url.absoluteString + "/")
}

/// Builds the github.com blob base URL used to resolve relative links in Markdown.
func githubBlobBaseURL(owner: String, repo: String, branch: String, directory: String = "") -> URL? {
    var url = URL(string: "https://github.com")!
        .appending(path: owner)
        .appending(path: repo)
        .appending(path: "blob")
        .appending(path: branch)
    if !directory.isEmpty {
        url = url.appending(path: directory)
    }
    return URL(string: url.absoluteString + "/")
}

/// Navigation value identifying a file inside a repository (used for in-app Markdown links).
struct RepoFileRef: Hashable {
    let owner: String
    let repo: String
    let branch: String
    let path: String

    var name: String { (path as NSString).lastPathComponent }
    var directory: String { (path as NSString).deletingLastPathComponent }
    /// Directory links are marked with a trailing slash (e.g. github.com …/tree/… URLs).
    var isDirectory: Bool { path.hasSuffix("/") }
    var isMarkdown: Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return ext == "md" || ext == "markdown"
    }
}

/// Navigation value identifying a repository by owner and name (a github.com link tapped
/// inside Markdown). The full `Repo` is fetched on demand by `LinkedRepoView`.
struct RepoLinkRef: Hashable {
    let owner: String
    let name: String
}

/// Something opened from a Markdown link or the file browser, shown inline
/// below the pinned README/Files picker (never pushed — nested NavigationStacks
/// break the outer stack's pushes on both iOS and macOS).
enum RepoLinkTarget: Hashable {
    /// A file — Markdown, plain text, or extension-less (probed before display).
    case file(RepoFileRef)
    /// A directory (path without trailing slash).
    case directory(RepoFileRef)
    /// Another repository.
    case repo(RepoLinkRef)

    static func target(for ref: RepoFileRef) -> RepoLinkTarget {
        if ref.isDirectory {
            return .directory(RepoFileRef(owner: ref.owner, repo: ref.repo,
                                          branch: ref.branch, path: String(ref.path.dropLast())))
        }
        return .file(ref)
    }
}

/// Routes a link tapped in rendered Markdown to an inline navigation target
/// or to the in-app web viewer. No link ever opens a system browser.
func handleMarkdownLink(_ link: MarkdownLink,
                        owner: String, repo: String, branch: String,
                        onOpenTarget: (RepoLinkTarget) -> Void,
                        webLink: Binding<IdentifiableURL?>) {
    switch link {
    case .sameRepoFile(let path):
        onOpenTarget(.target(for: RepoFileRef(owner: owner, repo: repo, branch: branch, path: path)))
    case .repoFile(let ref):
        onOpenTarget(.target(for: ref))
    case .repo(let linkedOwner, let name):
        onOpenTarget(.repo(RepoLinkRef(owner: linkedOwner, name: name)))
    case .web(let url):
        webLink.wrappedValue = IdentifiableURL(url: url)
    }
}

/// Loading indicator pinned to the top of the detail area instead of centered.
struct TopLoadingView: View {
    var label: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if let label {
                    ProgressView(label)
                } else {
                    ProgressView()
                }
            }
            .padding(.top, 48)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Repository detail

struct RepoDetailView: View {
    @Environment(AppSettings.self) private var settings
    let repo: Repo

    @State private var tab: DetailTab = .readme
    /// Current directory of the Files tab (empty = repository root). Browsing
    /// directories happens in-place so the README/Files picker stays visible.
    @State private var filesPath = ""
    /// Inline stack of content opened from Markdown links — shown below the
    /// pinned picker instead of replacing the page.
    @State private var opened: [RepoLinkTarget] = []

    enum DetailTab: CaseIterable, Identifiable {
        case readme, files

        var id: Self { self }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker(settings.tr(.view), selection: $tab) {
                Text("README").tag(DetailTab.readme)
                Text(settings.tr(.files)).tag(DetailTab.files)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            if let top = opened.last {
                openedHeader(top)
                openedContent(top)
                    .id(top)
            } else {
                tabContent
            }
        }
        #if os(macOS)
        .navigationTitle(repo.name)
        #else
        // Nothing above the pinned README/Files picker on iOS.
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .iOSHidesBackButton()
        // Switching tabs abandons whatever was opened from a link.
        .onChange(of: tab) { _, _ in opened.removeAll() }
        .fontSizeShortcuts(get: { settings.fontSize }, set: { settings.fontSize = $0 })
        #if os(iOS)
        // While inline link content is open, the nav-level swipe is suspended
        // (see SwipeBackControl) so a swipe can't skip a level; this drag pops
        // one inline level instead. The ‹ button in the header is the fallback.
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    guard !opened.isEmpty,
                          value.startLocation.x < 60,
                          value.translation.width > 50,
                          abs(value.translation.height) < 80 else { return }
                    opened.removeLast()
                }
        )
        .onAppear { updateSwipeOverride() }
        .onChange(of: opened.isEmpty) { _, _ in updateSwipeOverride() }
        .onDisappear { SwipeBackControl.overridePop = nil }
        #endif
    }

    #if os(iOS)
    private func updateSwipeOverride() {
        SwipeBackControl.overridePop = opened.isEmpty ? nil : { opened.removeLast() }
    }
    #endif

    /// Breadcrumb bar above opened link content: ‹ back + current path.
    private func openedHeader(_ target: RepoLinkTarget) -> some View {
        HStack(spacing: 8) {
            Button {
                opened.removeLast()
            } label: {
                Image(systemName: "chevron.left")
            }
            Text(title(for: target))
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.bottom, 6)
    }

    private func title(for target: RepoLinkTarget) -> String {
        switch target {
        case .file(let ref), .directory(let ref): return ref.path
        case .repo(let ref): return "\(ref.owner)/\(ref.name)"
        }
    }

    @ViewBuilder
    private func openedContent(_ target: RepoLinkTarget) -> some View {
        switch target {
        case .file(let ref):
            if ref.isMarkdown {
                MarkdownFileView(ref: ref, onOpenTarget: openTarget)
            } else if (ref.path as NSString).pathExtension.isEmpty {
                ResolvedLinkTargetView(ref: ref, onOpenTarget: openTarget)
            } else {
                TextFileView(ref: ref)
            }
        case .directory(let ref):
            DirectoryContentView(ref: ref, onOpenTarget: openTarget)
        case .repo(let ref):
            LinkedRepoView(ref: ref)
        }
    }

    /// Pushes an inline level (used by every child view's link handling).
    private var openTarget: (RepoLinkTarget) -> Void {
        { target in opened.append(target) }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .readme:
            ReadmeView(repo: repo, onOpenTarget: openTarget)
        case .files:
            VStack(spacing: 0) {
                if !filesPath.isEmpty {
                    // Breadcrumb bar: current directory at the top, tap ‹ to go up.
                    HStack(spacing: 8) {
                        Button {
                            filesPath = (filesPath as NSString).deletingLastPathComponent
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        Text(filesPath)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 6)
                }
                FileBrowserView(owner: repo.owner.login, repo: repo.name,
                                branch: repo.defaultBranch, path: filesPath,
                                onOpenTarget: { target in
                                    switch target {
                                    case .directory(let ref):
                                        // Directories browse in-place inside the Files tab.
                                        filesPath = ref.path
                                    default:
                                        opened.append(target)
                                    }
                                })
            }
        }
    }
}

// MARK: - Linked repository

/// Loads a repository by owner/name (a tapped github.com link) and then shows it
/// with the regular `RepoDetailView`.
struct LinkedRepoView: View {
    @Environment(GitHubAuthManager.self) private var auth
    @Environment(AppSettings.self) private var settings
    let ref: RepoLinkRef

    @State private var repo: Repo?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let repo {
                RepoDetailView(repo: repo)
            } else if let errorMessage {
                ContentUnavailableView {
                    Label(settings.tr(.loadFailed), systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button(settings.tr(.retry)) { Task { await load() } }
                }
            } else {
                TopLoadingView(label: settings.tr(.loading))
            }
        }
        #if os(macOS)
        .navigationTitle("\(ref.owner)/\(ref.name)")
        #else
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .iOSHidesBackButton()
        .task { await load() }
    }

    private func load() async {
        guard let client = auth.client else { return }
        errorMessage = nil
        do {
            repo = try await client.repo(owner: ref.owner, name: ref.name)
        } catch GitHubError.unauthorized {
            auth.logout()
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - README

private struct ReadmeView: View {
    @Environment(GitHubAuthManager.self) private var auth
    @Environment(AppSettings.self) private var settings
    let repo: Repo
    let onOpenTarget: (RepoLinkTarget) -> Void

    @State private var readme: String?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var webLink: IdentifiableURL?

    var body: some View {
        Group {
            if isLoading {
                TopLoadingView(label: settings.tr(.loadingReadme))
            } else if let errorMessage {
                ContentUnavailableView {
                    Label(settings.tr(.loadFailed), systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button(settings.tr(.retry)) { Task { await load() } }
                }
            } else if let readme {
                WebMarkdownView(
                    markdown: readme,
                    rawBaseURL: rawBaseURL(owner: repo.owner.login, repo: repo.name,
                                           branch: repo.defaultBranch),
                    blobBaseURL: githubBlobBaseURL(owner: repo.owner.login, repo: repo.name,
                                                   branch: repo.defaultBranch),
                    onOpenLink: { link in
                        handleMarkdownLink(link, owner: repo.owner.login, repo: repo.name,
                                           branch: repo.defaultBranch,
                                           onOpenTarget: onOpenTarget, webLink: $webLink)
                    },
                    imageLoader: auth.client?.imageData(from:),
                    fontSize: settings.fontSize)
            } else {
                ContentUnavailableView(settings.tr(.noReadme), systemImage: "doc.text.magnifyingglass")
            }
        }
        .sheet(item: $webLink) { WebPageView(url: $0.url) }
        .task { await load() }
    }

    private func load() async {
        guard let client = auth.client else { return }
        isLoading = true
        errorMessage = nil
        do {
            readme = try await client.readme(owner: repo.owner.login, repo: repo.name)?.text
        } catch GitHubError.unauthorized {
            auth.logout()
            return
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

