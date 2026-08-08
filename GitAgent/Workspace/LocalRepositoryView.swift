//
//  LocalRepositoryView.swift
//  GitAgent
//

#if os(macOS)
import SwiftUI
import PDFKit

/// Read-only browser for a locally linked working tree. Access is obtained
/// solely from the security-scoped bookmark saved when the location was linked.
struct LocalRepositoryView: View {
    @Environment(AppSettings.self) private var settings
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
                    LocalFileContentView(url: openedURL, rootURL: rootURL, onBack: { self.openedURL = nil })
                } else {
                    LocalFileBrowser(rootURL: rootURL, relativePath: $relativePath, onOpen: { openedURL = $0 })
                }
            } else {
                TopLoadingView(label: settings.tr(.loading))
            }
        }
        .navigationTitle("\(repo.name) — Local")
        .task { openBookmark() }
        .onDisappear { access = nil }
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
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                }
                .overlay(alignment: .topLeading) {
                    if !relativePath.isEmpty {
                        Button {
                            relativePath = (relativePath as NSString).deletingLastPathComponent
                        } label: {
                            Label(relativePath, systemImage: "chevron.left")
                        }
                        .padding(.horizontal)
                        .padding(.top, 6)
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
    let onBack: () -> Void
    @State private var data: Data?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) { Image(systemName: "chevron.left") }
                Text(url.lastPathComponent).lineLimit(1)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.bottom, 6)
            content
        }
        .task { load() }
    }

    @ViewBuilder private var content: some View {
        if let data {
            let ext = url.pathExtension.lowercased()
            if ["md", "markdown"].contains(ext), let text = String(data: data, encoding: .utf8) {
                WebMarkdownView(markdown: text, rawBaseURL: url.deletingLastPathComponent(),
                                fontSize: settings.fontSize)
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
        do { data = try Data(contentsOf: url, options: .mappedIfSafe) }
        catch { errorMessage = error.localizedDescription }
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
