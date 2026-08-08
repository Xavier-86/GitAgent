//
//  RemoteRepositoryView.swift
//  GitAgent
//
//  Read-only browser for a verified working tree reached over SSH.
//

import PDFKit
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct RemoteRepositoryView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SSHHostStore.self) private var hosts
    @Environment(WorkspaceStore.self) private var workspace
    @Environment(\.workspacePageID) private var workspacePageID

    let repo: Repo
    let location: RepositoryLocation

    @State private var route: SSHConnectionRoute?
    @State private var relativePath = ""
    @State private var openedPath: String?
    @State private var errorMessage: String?

    private var host: SSHHostConfig? {
        location.hostID.flatMap { id in hosts.hosts.first { $0.id == id } }
    }

    var body: some View {
        Group {
            if let errorMessage {
                ContentUnavailableView(
                    settings.tr(.remoteRepositoryUnavailable),
                    systemImage: "server.rack",
                    description: Text(errorMessage)
                )
            } else if let route {
                if let openedPath {
                    RemoteFileContentView(
                        route: route,
                        rootPath: location.path,
                        relativePath: openedPath,
                        onOpenPath: openPath
                    )
                    .id(openedPath)
                } else {
                    RemoteFileBrowser(
                        route: route,
                        rootPath: location.path,
                        relativePath: $relativePath,
                        onOpen: openItem
                    )
                }
            } else {
                TopLoadingView(label: settings.tr(.loading))
            }
        }
        .navigationTitle(
            "\(repo.name) — \(host?.locationDisplayName ?? settings.tr(.computerUnavailable))"
        )
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task(id: location.id) { resolveRoute() }
        .onAppear { syncContextualBackAction() }
        .onChange(of: openedPath) { syncContextualBackAction() }
        .onChange(of: relativePath) { syncContextualBackAction() }
        .onDisappear {
            if let workspacePageID {
                workspace.clearContextualBackAction(for: workspacePageID)
            }
        }
    }

    private func resolveRoute() {
        guard let host else {
            errorMessage = settings.tr(.computerUnavailable)
            return
        }
        do {
            route = try hosts.connectionRoute(for: host)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func openItem(_ item: RemoteRepositoryBrowser.Item) {
        switch item.kind {
        case .directory:
            relativePath = item.relativePath
        case .file:
            openedPath = item.relativePath
        }
    }

    private func openPath(_ path: String) {
        guard let route else { return }
        let normalized = Self.normalizedRelativePath(path)
        guard !normalized.isEmpty else {
            relativePath = ""
            openedPath = nil
            return
        }
        Task {
            do {
                let kind = try await SSHConnection.retryingTransientFailure {
                    try await RemoteRepositoryBrowser.kind(
                        route: route,
                        rootPath: location.path,
                        relativePath: normalized
                    )
                }
                switch kind {
                case .directory:
                    relativePath = normalized
                    openedPath = nil
                case .file:
                    openedPath = normalized
                }
            } catch {
                errorMessage = remoteRepositoryErrorMessage(error, settings: settings)
            }
        }
    }

    private static func normalizedRelativePath(_ path: String) -> String {
        path.split(separator: "/").reduce(into: [String]()) { components, component in
            switch component {
            case ".", "": break
            case "..": if !components.isEmpty { components.removeLast() }
            default: components.append(String(component))
            }
        }.joined(separator: "/")
    }

    private func syncContextualBackAction() {
        guard let workspacePageID else { return }
        let openedPath = $openedPath
        let relativePath = $relativePath
        workspace.setContextualBackAction(
            for: workspacePageID,
            isAvailable: openedPath.wrappedValue != nil || !relativePath.wrappedValue.isEmpty
        ) {
            if openedPath.wrappedValue != nil {
                openedPath.wrappedValue = nil
                return true
            }
            guard !relativePath.wrappedValue.isEmpty else { return false }
            relativePath.wrappedValue =
                (relativePath.wrappedValue as NSString).deletingLastPathComponent
            return true
        }
    }
}

private struct RemoteFileBrowser: View {
    @Environment(AppSettings.self) private var settings

    let route: SSHConnectionRoute
    let rootPath: String
    @Binding var relativePath: String
    let onOpen: (RemoteRepositoryBrowser.Item) -> Void

    @State private var items: [RemoteRepositoryBrowser.Item] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            if !relativePath.isEmpty {
                HStack {
                    Label(relativePath, systemImage: "folder")
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                Divider()
            }

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
                        Button { onOpen(item) } label: {
                            Label(item.name, systemImage: icon(for: item))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.primary)
                    }
                    .macTransparentScrollBackground()
                }
            }
        }
        .task(id: relativePath) { await load() }
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            items = try await SSHConnection.retryingTransientFailure {
                try await RemoteRepositoryBrowser.listItems(
                    route: route,
                    rootPath: rootPath,
                    relativePath: relativePath
                )
            }
        } catch {
            items = []
            errorMessage = remoteRepositoryErrorMessage(error, settings: settings)
        }
    }

    private func icon(for item: RemoteRepositoryBrowser.Item) -> String {
        if item.kind == .directory { return "folder" }
        let ext = (item.name as NSString).pathExtension.lowercased()
        if ["md", "markdown"].contains(ext) { return "doc.richtext" }
        if ["png", "jpg", "jpeg", "gif", "webp", "heic"].contains(ext) { return "photo" }
        if ext == "pdf" { return "doc.richtext" }
        return "doc.text"
    }
}

private struct RemoteFileContentView: View {
    @Environment(AppSettings.self) private var settings

    let route: SSHConnectionRoute
    let rootPath: String
    let relativePath: String
    let onOpenPath: (String) -> Void

    @State private var data: Data?
    @State private var errorMessage: String?
    @State private var webLink: IdentifiableURL?

    private let repositoryRootURL = URL(string: "gitagent-remote://repository/")!

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text((relativePath as NSString).lastPathComponent)
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
        .task(id: relativePath) { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if let data {
            let ext = (relativePath as NSString).pathExtension.lowercased()
            if ["md", "markdown"].contains(ext),
               let text = String(data: data, encoding: .utf8) {
                WebMarkdownView(
                    markdown: text,
                    rawBaseURL: documentDirectoryURL,
                    blobBaseURL: documentDirectoryURL,
                    repositoryRootURL: repositoryRootURL,
                    onOpenLink: openMarkdownLink,
                    imageLoader: loadRemoteImage,
                    fontSize: settings.fontSize
                )
            } else if ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff"].contains(ext) {
                remoteImage(data)
            } else if ext == "pdf", let document = PDFDocument(data: data) {
                RemotePDFKitView(document: document)
            } else if let text = String(data: data, encoding: .utf8) {
                WebMarkdownView(markdown: "```\n\(text)\n```", fontSize: settings.fontSize)
            } else {
                ContentUnavailableView(settings.tr(.previewUnavailable), systemImage: "doc")
            }
        } else if let errorMessage {
            ContentUnavailableView(
                settings.tr(.loadFailed),
                systemImage: "exclamationmark.triangle",
                description: Text(errorMessage)
            )
        } else {
            TopLoadingView(label: settings.tr(.loading))
        }
    }

    @ViewBuilder
    private func remoteImage(_ data: Data) -> some View {
        #if os(macOS)
        if let image = NSImage(data: data) {
            ScrollView { Image(nsImage: image).resizable().scaledToFit().padding() }
        } else {
            ContentUnavailableView(settings.tr(.previewUnavailable), systemImage: "photo")
        }
        #else
        if let image = UIImage(data: data) {
            ScrollView { Image(uiImage: image).resizable().scaledToFit().padding() }
        } else {
            ContentUnavailableView(settings.tr(.previewUnavailable), systemImage: "photo")
        }
        #endif
    }

    private var documentDirectoryURL: URL {
        let directory = (relativePath as NSString).deletingLastPathComponent
        guard !directory.isEmpty else { return repositoryRootURL }
        return repositoryRootURL.appending(path: directory, directoryHint: .isDirectory)
    }

    @MainActor
    private func load() async {
        data = nil
        errorMessage = nil
        do {
            data = try await SSHConnection.retryingTransientFailure {
                try await RemoteRepositoryBrowser.readFile(
                    route: route,
                    rootPath: rootPath,
                    relativePath: relativePath
                )
            }
        } catch {
            errorMessage = remoteRepositoryErrorMessage(error, settings: settings)
        }
    }

    private func loadRemoteImage(_ imageURL: URL) async throws -> (data: Data, mimeType: String) {
        guard imageURL.scheme == repositoryRootURL.scheme,
              imageURL.host() == repositoryRootURL.host() else {
            throw URLError(.unsupportedURL)
        }
        let path = imageURL.pathComponents.filter { $0 != "/" }.joined(separator: "/")
        let data = try await SSHConnection.retryingTransientFailure {
            try await RemoteRepositoryBrowser.readFile(
                route: route,
                rootPath: rootPath,
                relativePath: path
            )
        }
        let mimeType = UTType(filenameExtension: (path as NSString).pathExtension)?.preferredMIMEType
            ?? "application/octet-stream"
        return (data, mimeType)
    }

    private func openMarkdownLink(_ link: MarkdownLink) {
        switch link {
        case .sameRepoFile(let path):
            onOpenPath(path)
        case .repoFile(let ref):
            openWebLink(githubURL(owner: ref.owner, repo: ref.repo, branch: ref.branch,
                                  path: ref.path, isDirectory: ref.isDirectory))
        case .repo(let owner, let name):
            openWebLink(githubURL(owner: owner, repo: name))
        case .web(let url):
            openWebLink(url)
        }
    }

    private func githubURL(
        owner: String,
        repo: String,
        branch: String? = nil,
        path: String = "",
        isDirectory: Bool = false
    ) -> URL? {
        var url = URL(string: "https://github.com")!
            .appending(path: owner)
            .appending(path: repo)
        if let branch {
            url = url
                .appending(path: isDirectory ? "tree" : "blob")
                .appending(path: branch)
            if !path.isEmpty {
                url = url.appending(
                    path: path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                )
            }
        }
        return url
    }

    private func openWebLink(_ url: URL?) {
        guard let url else { return }
        webLink = IdentifiableURL(url: url)
    }
}

private struct RemotePDFKitView: View {
    let document: PDFDocument

    var body: some View {
        #if os(macOS)
        RemotePDFKitNSView(document: document)
        #else
        RemotePDFKitUIView(document: document)
        #endif
    }
}

#if os(macOS)
private struct RemotePDFKitNSView: NSViewRepresentable {
    let document: PDFDocument

    func makeNSView(context: Context) -> PDFView {
        configuredView()
    }

    func updateNSView(_ view: PDFView, context: Context) {
        view.document = document
    }

    private func configuredView() -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = document
        return view
    }
}
#else
private struct RemotePDFKitUIView: UIViewRepresentable {
    let document: PDFDocument

    func makeUIView(context: Context) -> PDFView {
        configuredView()
    }

    func updateUIView(_ view: PDFView, context: Context) {
        view.document = document
    }

    private func configuredView() -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = document
        return view
    }
}
#endif

private func remoteRepositoryErrorMessage(
    _ error: Error,
    settings: AppSettings
) -> String {
    guard let error = error as? RemoteRepositoryBrowser.BrowserError else {
        return error.localizedDescription
    }
    switch error {
    case .pathMissing:
        return settings.tr(.repositoryPathMissing)
    case .outsideRepository:
        return settings.tr(.repositoryPathOutsideRoot)
    case .fileTooLarge:
        return settings.tr(.fileTooLargeToPreview)
    case .invalidResponse:
        return settings.tr(.invalidResponse)
    }
}
