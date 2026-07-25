//
//  RepoDetailView.swift
//  GitAgent
//

import SwiftUI

/// Builds the raw.githubusercontent.com base URL used to resolve relative image paths in Markdown.
private func rawBaseURL(owner: String, repo: String, branch: String, directory: String = "") -> URL? {
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
private func githubBlobBaseURL(owner: String, repo: String, branch: String, directory: String = "") -> URL? {
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

/// Routes a link tapped in rendered Markdown to in-app navigation (repository/file pages)
/// or to the in-app web viewer for anything else. No link ever opens a system browser.
private func handleMarkdownLink(_ link: MarkdownLink,
                                owner: String, repo: String, branch: String,
                                navigationPath: Binding<NavigationPath>,
                                webLink: Binding<IdentifiableURL?>) {
    switch link {
    case .sameRepoFile(let path):
        navigationPath.wrappedValue.append(RepoFileRef(owner: owner, repo: repo, branch: branch, path: path))
    case .repoFile(let ref):
        navigationPath.wrappedValue.append(ref)
    case .repo(let linkedOwner, let name):
        navigationPath.wrappedValue.append(RepoLinkRef(owner: linkedOwner, name: name))
    case .web(let url):
        webLink.wrappedValue = IdentifiableURL(url: url)
    }
}

/// Loads a repository by owner/name (a tapped github.com link) and then shows it
/// with the regular `RepoDetailView`.
struct LinkedRepoView: View {
    @Environment(GitHubAuthManager.self) private var auth
    @Environment(AppSettings.self) private var settings
    let ref: RepoLinkRef
    let navigationPath: Binding<NavigationPath>

    @State private var repo: Repo?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let repo {
                RepoDetailView(repo: repo, navigationPath: navigationPath)
            } else if let errorMessage {
                ContentUnavailableView {
                    Label(settings.tr(.loadFailed), systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button(settings.tr(.retry)) { Task { await load() } }
                }
            } else {
                ProgressView(settings.tr(.loading))
            }
        }
        .navigationTitle("\(ref.owner)/\(ref.name)")
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

struct RepoDetailView: View {
    @Environment(AppSettings.self) private var settings
    let repo: Repo
    let navigationPath: Binding<NavigationPath>

    @State private var tab: DetailTab = .readme

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

            switch tab {
            case .readme:
                ReadmeView(repo: repo, navigationPath: navigationPath)
            case .files:
                FileBrowserView(owner: repo.owner.login, repo: repo.name,
                                branch: repo.defaultBranch, path: "",
                                navigationPath: navigationPath)
            }
        }
        .navigationTitle(repo.name)
    }
}

// MARK: - README

private struct ReadmeView: View {
    @Environment(GitHubAuthManager.self) private var auth
    @Environment(AppSettings.self) private var settings
    let repo: Repo
    let navigationPath: Binding<NavigationPath>

    @State private var readme: String?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var webLink: IdentifiableURL?

    var body: some View {
        Group {
            if isLoading {
                ProgressView(settings.tr(.loadingReadme))
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
                                           navigationPath: navigationPath, webLink: $webLink)
                    },
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

// MARK: - File browser

struct FileBrowserView: View {
    @Environment(GitHubAuthManager.self) private var auth
    @Environment(AppSettings.self) private var settings
    let owner: String
    let repo: String
    let branch: String
    let path: String
    let navigationPath: Binding<NavigationPath>

    @State private var items: [RepoContent] = []
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
            } else if items.isEmpty {
                ContentUnavailableView(settings.tr(.emptyFolder), systemImage: "folder")
            } else {
                List(items) { item in
                    switch item.type {
                    case .dir:
                        NavigationLink {
                            FileBrowserView(owner: owner, repo: repo, branch: branch, path: item.path,
                                            navigationPath: navigationPath)
                        } label: {
                            Label(item.name, systemImage: "folder")
                        }
                    case .file:
                        NavigationLink {
                            destinationView(for: item)
                        } label: {
                            Label(item.name, systemImage: item.isMarkdown ? "doc.richtext" : "doc.text")
                        }
                    default:
                        Label(item.name, systemImage: "doc")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(path.isEmpty ? repo : (path as NSString).lastPathComponent)
        .task { await load() }
    }

    @ViewBuilder
    private func destinationView(for item: RepoContent) -> some View {
        let ref = RepoFileRef(owner: owner, repo: repo, branch: branch, path: item.path)
        if item.isMarkdown {
            MarkdownFileView(ref: ref, navigationPath: navigationPath)
        } else {
            TextFileView(ref: ref)
        }
    }

    private func load() async {
        guard let client = auth.client else { return }
        isLoading = true
        errorMessage = nil
        do {
            items = try await client.contents(owner: owner, repo: repo, path: path)
        } catch GitHubError.unauthorized {
            auth.logout()
            return
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - File content

struct MarkdownFileView: View {
    @Environment(GitHubAuthManager.self) private var auth
    @Environment(AppSettings.self) private var settings
    let ref: RepoFileRef
    let navigationPath: Binding<NavigationPath>

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
                                           navigationPath: navigationPath, webLink: $webLink)
                    },
                    fontSize: settings.fontSize)
            } else if let errorMessage {
                ContentUnavailableView(settings.tr(.loadFailed), systemImage: "exclamationmark.triangle",
                                       description: Text(errorMessage))
            } else {
                ProgressView()
            }
        }
        .navigationTitle(ref.name)
        .sheet(item: $webLink) { WebPageView(url: $0.url) }
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
                ProgressView()
            }
        }
        .navigationTitle(ref.name)
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
