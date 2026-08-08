//
//  LocalRepositoryView.swift
//  GitAgent
//

#if os(macOS)
import SwiftUI
import PDFKit
import UniformTypeIdentifiers

/// Read-only browser for a locally linked working tree. Access is obtained
/// solely from the security-scoped bookmark saved when the location was linked.
struct LocalRepositoryView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(WorkspaceStore.self) private var workspace
    @Environment(\.workspacePageID) private var workspacePageID
    let repo: Repo
    let location: RepositoryLocation

    @State private var rootURL: URL?
    @State private var relativePath = ""
    @State private var openedURL: URL?
    @State private var errorMessage: String?
    @State private var access: LocalRepositoryAccess?

    var body: some View {
        VStack(spacing: 0) {
            if let errorMessage {
                ContentUnavailableView("Local Repository Unavailable", systemImage: "externaldrive.badge.exclamationmark",
                                       description: Text(errorMessage))
            } else if let rootURL {
                if let openedURL {
                    LocalFileContentView(
                        url: openedURL,
                        rootURL: rootURL,
                        onOpen: { openLocalTarget($0, rootURL: rootURL) }
                    )
                    .id(openedURL)
                } else {
                    LocalFileBrowser(rootURL: rootURL, relativePath: $relativePath, onOpen: { openedURL = $0 })
                }
            } else {
                TopLoadingView(label: settings.tr(.loading))
            }
        }
        .navigationTitle("\(repo.name) — \(settings.tr(.thisMac))")
        .task { openBookmark() }
        .onAppear { syncContextualBackAction() }
        .onChange(of: openedURL) { syncContextualBackAction() }
        .onChange(of: relativePath) { syncContextualBackAction() }
        .onDisappear {
            if let workspacePageID {
                workspace.clearContextualBackAction(for: workspacePageID)
            }
            access = nil
        }
    }

    private func openLocalTarget(_ targetURL: URL, rootURL: URL) {
        guard let targetURL = LocalRepositoryPath.containedURL(targetURL, rootURL: rootURL),
              FileManager.default.fileExists(atPath: targetURL.path) else { return }
        if LocalRepositoryPath.isDirectory(targetURL) {
            relativePath = LocalRepositoryPath.relativePath(targetURL, rootURL: rootURL) ?? ""
            openedURL = nil
        } else {
            openedURL = targetURL
        }
    }

    private func openBookmark() {
        guard rootURL == nil else { return }
        guard let bookmark = location.bookmarkData else {
            errorMessage = settings.tr(.localRepositoryAccessDenied)
            return
        }
        do {
            let access = try LocalRepositoryAccess(bookmarkData: bookmark)
            self.access = access
            rootURL = access.url
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func syncContextualBackAction() {
        guard let workspacePageID else { return }
        let openedURL = $openedURL
        let relativePath = $relativePath
        workspace.setContextualBackAction(
            for: workspacePageID,
            isAvailable: openedURL.wrappedValue != nil || !relativePath.wrappedValue.isEmpty
        ) {
            if openedURL.wrappedValue != nil {
                openedURL.wrappedValue = nil
                return true
            }
            guard !relativePath.wrappedValue.isEmpty else { return false }
            relativePath.wrappedValue =
                (relativePath.wrappedValue as NSString).deletingLastPathComponent
            return true
        }
    }
}

/// Resolves local Markdown targets without allowing links or symlinks to leave
/// the working tree selected by the user.
private enum LocalRepositoryPath {
    static func containedURL(_ candidate: URL, rootURL: URL) -> URL? {
        let root = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        let target = candidate.standardizedFileURL.resolvingSymlinksInPath()
        let rootPath = root.path
        let targetPath = target.path
        guard targetPath == rootPath || targetPath.hasPrefix(rootPath + "/") else {
            return nil
        }
        return target
    }

    static func relativePath(_ targetURL: URL, rootURL: URL) -> String? {
        guard let target = containedURL(targetURL, rootURL: rootURL),
              let root = containedURL(rootURL, rootURL: rootURL) else { return nil }
        guard target.path != root.path else { return "" }
        return String(target.path.dropFirst(root.path.count + 1))
    }

    static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}

private final class LocalRepositoryAccess {
    let url: URL

    init(bookmarkData: Data) throws {
        var stale = false
        url = try URL(resolvingBookmarkData: bookmarkData, options: [.withSecurityScope],
                      relativeTo: nil, bookmarkDataIsStale: &stale)
        guard !stale, url.startAccessingSecurityScopedResource() else {
            throw RepositoryLocationVerifier.VerificationError.localAccessDenied
        }
    }

    deinit { url.stopAccessingSecurityScopedResource() }
}

private struct LocalFileBrowser: View {
    @Environment(AppSettings.self) private var settings
    let rootURL: URL
    @Binding var relativePath: String
    let onOpen: (URL) -> Void
    @State private var items: [URL] = []
    @State private var errorMessage: String?

    private var directoryURL: URL { rootURL.appending(path: relativePath, directoryHint: .isDirectory) }

    var body: some View {
        Group {
            if let errorMessage {
                ContentUnavailableView(settings.tr(.loadFailed), systemImage: "exclamationmark.triangle",
                                       description: Text(errorMessage))
            } else {
                List(items, id: \.self) { url in
                    Button {
                        if isDirectory(url) {
                            relativePath = relativePath.isEmpty ? url.lastPathComponent : "\(relativePath)/\(url.lastPathComponent)"
                        } else {
                            onOpen(url)
                        }
                    } label: {
                        Label(url.lastPathComponent, systemImage: isDirectory(url) ? "folder" : icon(for: url))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                }
                .safeAreaInset(edge: .top) {
                    if !relativePath.isEmpty {
                        HStack {
                            Label(relativePath, systemImage: "folder")
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(.bar)
                    }
                }
            }
        }
        .task(id: relativePath) { load() }
    }

    private func load() {
        do {
            items = try FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
                options: [.skipsHiddenFiles]
            ).sorted {
                let leftDirectory = isDirectory($0)
                let rightDirectory = isDirectory($1)
                if leftDirectory != rightDirectory { return leftDirectory }
                return $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private func icon(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if ["md", "markdown"].contains(ext) { return "doc.richtext" }
        if ["png", "jpg", "jpeg", "gif", "webp", "heic"].contains(ext) { return "photo" }
        if ext == "pdf" { return "doc.richtext" }
        return "doc.text"
    }
}

private struct LocalFileContentView: View {
    @Environment(AppSettings.self) private var settings
    let url: URL
    let rootURL: URL
    let onOpen: (URL) -> Void
    @State private var data: Data?
    @State private var errorMessage: String?
    @State private var webLink: IdentifiableURL?

    private let repositoryRootURL = URL(string: "gitagent-local://repository/")!

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(url.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            Divider()
            content
        }
        .sheet(item: $webLink) { WebPageView(url: $0.url) }
        .task(id: url) { load() }
    }

    @ViewBuilder private var content: some View {
        if let data {
            let ext = url.pathExtension.lowercased()
            if ["md", "markdown"].contains(ext), let text = String(data: data, encoding: .utf8) {
                WebMarkdownView(
                    markdown: text,
                    rawBaseURL: documentDirectoryURL,
                    blobBaseURL: documentDirectoryURL,
                    repositoryRootURL: repositoryRootURL,
                    onOpenLink: openMarkdownLink,
                    imageLoader: loadLocalImage,
                    fontSize: settings.fontSize
                )
            } else if ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff"].contains(ext),
                      let image = NSImage(data: data) {
                ScrollView { Image(nsImage: image).resizable().scaledToFit().padding() }
            } else if ext == "pdf", let document = PDFDocument(data: data) {
                LocalPDFKitView(document: document)
            } else if let text = String(data: data, encoding: .utf8) {
                WebMarkdownView(markdown: "```\n\(text)\n```", fontSize: settings.fontSize)
            } else {
                ContentUnavailableView("Preview Unavailable", systemImage: "doc")
            }
        } else if let errorMessage {
            ContentUnavailableView(settings.tr(.loadFailed), systemImage: "exclamationmark.triangle",
                                   description: Text(errorMessage))
        } else {
            TopLoadingView(label: settings.tr(.loading))
        }
    }

    private func load() {
        data = nil
        errorMessage = nil
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadLocalImage(_ imageURL: URL) async throws -> (data: Data, mimeType: String) {
        guard imageURL.scheme == repositoryRootURL.scheme,
              imageURL.host() == repositoryRootURL.host() else {
            throw URLError(.unsupportedURL)
        }
        let relativePath = imageURL.pathComponents.filter { $0 != "/" }.joined(separator: "/")
        guard let imageURL = LocalRepositoryPath.containedURL(
            rootURL.appending(path: relativePath),
            rootURL: rootURL
        ), !LocalRepositoryPath.isDirectory(imageURL) else {
            throw URLError(.noPermissionsToReadFile)
        }
        let data = try Data(contentsOf: imageURL, options: .mappedIfSafe)
        let mimeType = UTType(filenameExtension: imageURL.pathExtension)?.preferredMIMEType
            ?? "application/octet-stream"
        return (data, mimeType)
    }

    private var documentDirectoryURL: URL {
        guard let relativePath = LocalRepositoryPath.relativePath(url, rootURL: rootURL) else {
            return repositoryRootURL
        }
        let directory = (relativePath as NSString).deletingLastPathComponent
        guard !directory.isEmpty else { return repositoryRootURL }
        return repositoryRootURL.appending(path: directory, directoryHint: .isDirectory)
    }

    private func openMarkdownLink(_ link: MarkdownLink) {
        switch link {
        case .sameRepoFile(let path):
            onOpen(rootURL.appending(path: path))
        case .repoFile(let ref):
            openWebLink(githubURL(owner: ref.owner, repo: ref.repo, branch: ref.branch,
                                  path: ref.path, isDirectory: ref.isDirectory))
        case .repo(let owner, let name):
            openWebLink(githubURL(owner: owner, repo: name))
        case .web(let url):
            openWebLink(url)
        }
    }

    private func githubURL(owner: String, repo: String, branch: String? = nil,
                           path: String = "", isDirectory: Bool = false) -> URL? {
        var url = URL(string: "https://github.com")!
            .appending(path: owner)
            .appending(path: repo)
        if let branch {
            url = url
                .appending(path: isDirectory ? "tree" : "blob")
                .appending(path: branch)
            if !path.isEmpty {
                url = url.appending(path: path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
            }
        }
        return url
    }

    private func openWebLink(_ url: URL?) {
        guard let url else { return }
        webLink = IdentifiableURL(url: url)
    }
}

private struct LocalPDFKitView: NSViewRepresentable {
    let document: PDFDocument
    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = document
        return view
    }
    func updateNSView(_ view: PDFView, context: Context) { view.document = document }
}
#endif
