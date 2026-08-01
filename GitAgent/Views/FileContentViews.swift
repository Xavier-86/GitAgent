//
//  FileContentViews.swift
//  GitAgent
//
//  File/directory viewers shown inside RepoDetailView's inline link stack.
//

import SwiftUI

// MARK: - File browser

struct FileBrowserView: View {
    @Environment(GitHubAuthManager.self) private var auth
    @Environment(AppSettings.self) private var settings
    let owner: String
    let repo: String
    let branch: String
    let path: String
    /// Tapping a directory or file reports a target instead of pushing a page —
    /// the parent decides whether to browse in-place or open it inline.
    let onOpenTarget: (RepoLinkTarget) -> Void

    @State private var items: [RepoContent] = []
    @State private var commits: [String: FileCommit] = [:]
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                TopLoadingView(label: settings.tr(.loading))
            } else if let errorMessage {
                ContentUnavailableView {
                    Label(settings.tr(.loadFailed), systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button(settings.tr(.retry)) { Task { await load() } }
                }
            } else if items.isEmpty {
                ContentUnavailableView(settings.tr(.emptyFolder), systemImage: "folder")
            } else {
                List(items) { item in
                    switch item.effectiveType {
                    case .dir:
                        Button {
                            onOpenTarget(.directory(makeRef(for: item)))
                        } label: {
                            rowLabel(item, icon: "folder")
                        }
                        // plain: iOS 26 would otherwise draw a tinted capsule
                        // background behind every list-row button.
                        .buttonStyle(.plain)
                        .foregroundStyle(.primary)
                    case .file:
                        Button {
                            onOpenTarget(.file(makeRef(for: item)))
                        } label: {
                            rowLabel(item, icon: item.isMarkdown ? "doc.richtext" : "doc.text")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.primary)
                    case .submodule:
                        // A submodule points to another repository — open that.
                        if let repoRef = item.submoduleRepoRef(fallbackOwner: owner) {
                            Button {
                                onOpenTarget(.repo(repoRef))
                            } label: {
                                rowLabel(item, icon: "shippingbox")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.primary)
                        } else {
                            rowLabel(item, icon: "shippingbox")
                                .foregroundStyle(.secondary)
                        }
                    default:
                        rowLabel(item, icon: "doc")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .iOSHidesBackButton()
        .macTransparentScrollBackground()
        .task(id: path) { await load() }
    }

    /// GitHub-web style columns: name in a fixed-width column on the left,
    /// latest-commit headline left-aligned in the flexible middle (so all
    /// headlines share one vertical edge), (static) time on the right.
    private var nameColumnWidth: CGFloat {
        #if os(macOS)
        260
        #else
        140
        #endif
    }

    private func rowLabel(_ item: RepoContent, icon: String) -> some View {
        HStack(spacing: 12) {
            Label(item.name, systemImage: icon)
                .lineLimit(1)
                .frame(width: nameColumnWidth, alignment: .leading)
            if let commit = commits[item.path] {
                Text(commit.messageHeadline)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(RelativeTime.short(commit.committedDate))
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func makeRef(for item: RepoContent) -> RepoFileRef {
        RepoFileRef(owner: owner, repo: repo, branch: branch, path: item.path)
    }

    private func load() async {
        guard let client = auth.client else { return }
        isLoading = true
        errorMessage = nil
        commits = [:]
        do {
            items = try await client.contents(owner: owner, repo: repo, path: path)
        } catch GitHubError.unauthorized {
            auth.logout()
            return
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
        // Commit info is decorative — it fills in after the listing appears
        // and never blocks it.
        guard !items.isEmpty else { return }
        commits = await client.latestCommits(
            owner: owner, repo: repo, ref: branch, paths: items.map(\.path))
    }
}

// MARK: - Directory (with submodule redirect)

/// Directory view for link targets. README links to submodules are
/// directory-shaped — probe once and open the linked repository instead.
struct DirectoryContentView: View {
    @Environment(GitHubAuthManager.self) private var auth
    let ref: RepoFileRef
    let onOpenTarget: (RepoLinkTarget) -> Void

    @State private var submoduleRef: RepoLinkRef?
    @State private var checked = false

    var body: some View {
        Group {
            if let submoduleRef {
                LinkedRepoView(ref: submoduleRef)
            } else if checked {
                FileBrowserView(owner: ref.owner, repo: ref.repo, branch: ref.branch,
                                path: ref.path, onOpenTarget: onOpenTarget)
            } else {
                TopLoadingView()
            }
        }
        .task {
            guard let client = auth.client else { return }
            if let entry = try? await client.submoduleEntry(owner: ref.owner, repo: ref.repo,
                                                            path: ref.path, ref: ref.branch) {
                submoduleRef = entry.submoduleRepoRef(fallbackOwner: ref.owner)
            }
            checked = true
        }
    }
}

// MARK: - Ambiguous link resolver

/// Resolves an ambiguous Markdown link target (no file extension — could be a
/// directory like `docs`, an extension-less file like `LICENSE`, or a
/// submodule) by asking the API, then shows the right view.
struct ResolvedLinkTargetView: View {
    @Environment(GitHubAuthManager.self) private var auth
    let ref: RepoFileRef
    let onOpenTarget: (RepoLinkTarget) -> Void

    @State private var submoduleRef: RepoLinkRef?
    @State private var isDirectory: Bool?

    var body: some View {
        Group {
            if let submoduleRef {
                LinkedRepoView(ref: submoduleRef)
            } else if let isDirectory {
                if isDirectory {
                    FileBrowserView(owner: ref.owner, repo: ref.repo, branch: ref.branch,
                                    path: ref.path, onOpenTarget: onOpenTarget)
                } else {
                    TextFileView(ref: ref)
                }
            } else {
                TopLoadingView()
            }
        }
        .task {
            guard let client = auth.client else { return }
            if let entry = try? await client.submoduleEntry(owner: ref.owner, repo: ref.repo,
                                                            path: ref.path, ref: ref.branch),
               let repoRef = entry.submoduleRepoRef(fallbackOwner: ref.owner) {
                submoduleRef = repoRef
                return
            }
            isDirectory = (try? await client.isDirectory(owner: ref.owner, repo: ref.repo,
                                                         path: ref.path, ref: ref.branch)) ?? false
        }
    }
}

// MARK: - Markdown file

struct MarkdownFileView: View {
    @Environment(GitHubAuthManager.self) private var auth
    @Environment(AppSettings.self) private var settings
    let ref: RepoFileRef
    let onOpenTarget: (RepoLinkTarget) -> Void

    @State private var text: String?
    @State private var errorMessage: String?
    @State private var webLink: IdentifiableURL?

    var body: some View {
        Group {
            if let text {
                WebMarkdownView(
                    markdown: text,
                    rawBaseURL: rawBaseURL(owner: ref.owner, repo: ref.repo, branch: ref.branch,
                                           directory: ref.directory),
                    blobBaseURL: githubBlobBaseURL(owner: ref.owner, repo: ref.repo, branch: ref.branch,
                                                   directory: ref.directory),
                    onOpenLink: { link in
                        handleMarkdownLink(link, owner: ref.owner, repo: ref.repo,
                                           branch: ref.branch,
                                           onOpenTarget: onOpenTarget, webLink: $webLink)
                    },
                    imageLoader: auth.client?.imageData(from:),
                    fontSize: settings.fontSize)
            } else if let errorMessage {
                ContentUnavailableView(settings.tr(.loadFailed), systemImage: "exclamationmark.triangle",
                                       description: Text(errorMessage))
            } else {
                TopLoadingView()
            }
        }
        .sheet(item: $webLink) { WebPageView(url: $0.url) }
        .fontSizeShortcuts(get: { settings.fontSize }, set: { settings.fontSize = $0 })
        .task { await load() }
    }

    private func load() async {
        guard let client = auth.client else { return }
        do {
            text = try await client.fileText(owner: ref.owner, repo: ref.repo, path: ref.path, ref: ref.branch)
        } catch GitHubError.unauthorized {
            auth.logout()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Plain-text file

/// Plain-text file preview. Renders through the WebView pipeline as a fenced
/// code block so it gets syntax highlighting for free.
struct TextFileView: View {
    @Environment(GitHubAuthManager.self) private var auth
    @Environment(AppSettings.self) private var settings
    let ref: RepoFileRef

    @State private var text: String?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let text {
                WebMarkdownView(
                    markdown: Self.fenced(text, language: Self.languageName(for: ref.name)),
                    fontSize: settings.fontSize)
            } else if let errorMessage {
                ContentUnavailableView(settings.tr(.loadFailed), systemImage: "exclamationmark.triangle",
                                       description: Text(errorMessage))
            } else {
                TopLoadingView()
            }
        }
        .fontSizeShortcuts(get: { settings.fontSize }, set: { settings.fontSize = $0 })
        .task { await load() }
    }

    /// Maps a file extension to a highlight.js language identifier.
    private static func languageName(for filename: String) -> String {
        switch (filename as NSString).pathExtension.lowercased() {
        case "swift": return "swift"
        case "py": return "python"
        case "js", "mjs", "jsx": return "javascript"
        case "ts", "tsx": return "typescript"
        case "cpp", "cc", "cxx", "hpp", "hh", "h": return "cpp"
        case "c": return "c"
        case "m", "mm": return "objectivec"
        case "java": return "java"
        case "kt", "kts": return "kotlin"
        case "go": return "go"
        case "rs": return "rust"
        case "rb": return "ruby"
        case "php": return "php"
        case "cs": return "csharp"
        case "json": return "json"
        case "yml", "yaml": return "yaml"
        case "xml", "html", "htm": return "xml"
        case "css", "scss", "less": return "css"
        case "sh", "bash", "zsh": return "bash"
        case "sql": return "sql"
        case "toml", "ini", "cfg": return "ini"
        case "lua": return "lua"
        case "r": return "r"
        case "pl": return "perl"
        default: return "plaintext"
        }
    }

    /// Wraps file content in a code fence longer than any backtick run inside it.
    private static func fenced(_ text: String, language: String) -> String {
        var fence = "```"
        while text.contains(fence) { fence += "`" }
        return "\(fence)\(language)\n\(text)\n\(fence)"
    }

    private func load() async {
        guard let client = auth.client else { return }
        do {
            text = try await client.fileText(owner: ref.owner, repo: ref.repo, path: ref.path, ref: ref.branch)
        } catch GitHubError.unauthorized {
            auth.logout()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
