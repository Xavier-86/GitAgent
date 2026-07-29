//
//  WebMarkdownView.swift
//  GitAgent
//

import SwiftUI
import WebKit

// MARK: - Web asset installation

/// Copies the rendering assets bundled with the app (markdown-it / KaTeX /
/// highlight.js / CSS / fonts, plus the xterm.js terminal page) into
/// Application Support so the on-disk layout is deterministic —
/// katex.min.css resolves fonts via a relative `fonts/` path.
enum WebAssets {
    /// Bump this when the bundled assets change to force re-installation.
    private static let version = "9"

    /// Installed once per app launch — web views (one per chat bubble) must
    /// not hit the file system for the version check on every creation.
    static let sharedDirectory: URL? = installedDirectory()

    private static let assetFiles = [
        "template.html",
        "markdown-it.min.js",
        "katex.min.js",
        "auto-render.min.js",
        "katex.min.css",
        "github-markdown.css",
        "highlight.min.js",
        "hljs-github.min.css",
        "hljs-github-dark.min.css",
        // SSH terminal (xterm.js).
        "terminal.html",
        "xterm.min.js",
        "xterm.min.css",
        "addon-fit.min.js",
    ]

    static func installedDirectory() -> URL? {
        let fm = FileManager.default
        guard let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = support.appending(path: "GitAgent/web", directoryHint: .isDirectory)
        let marker = dir.appending(path: ".version")
        if (try? String(contentsOf: marker, encoding: .utf8)) == version { return dir }

        do {
            try? fm.removeItem(at: dir)
            try fm.createDirectory(at: dir.appending(path: "fonts", directoryHint: .isDirectory),
                                   withIntermediateDirectories: true)

            for name in assetFiles {
                let base = (name as NSString).deletingPathExtension
                let ext = (name as NSString).pathExtension
                guard let source = Bundle.main.url(forResource: base, withExtension: ext) else {
                    NSLog("GitAgent: missing web asset \(name)")
                    continue
                }
                try fm.copyItem(at: source, to: dir.appending(path: name))
            }

            // KaTeX fonts (flattened at the bundle root by Xcode, collected into fonts/ here).
            if let fonts = Bundle.main.urls(forResourcesWithExtension: "woff2", subdirectory: nil) {
                for font in fonts {
                    try? fm.copyItem(at: font, to: dir.appending(path: "fonts/\(font.lastPathComponent)"))
                }
            }

            try version.write(to: marker, atomically: true, encoding: .utf8)
            return dir
        } catch {
            NSLog("GitAgent: failed to install web assets \(error)")
            return nil
        }
    }
}

// MARK: - Link routing

/// Downloads image data for a URL (used to load GitHub-hosted images with auth).
typealias MarkdownImageLoader = (URL) async throws -> (data: Data, mimeType: String)

/// A link tapped inside rendered Markdown, classified for in-app navigation.
enum MarkdownLink {
    /// Relative link resolved inside the repository the document belongs to.
    case sameRepoFile(path: String)
    /// File in another repository (github.com blob or raw.githubusercontent.com URL).
    case repoFile(RepoFileRef)
    /// Repository page on github.com.
    case repo(owner: String, name: String)
    /// Any other web page (shown in the in-app web viewer).
    case web(URL)
}

// MARK: - SwiftUI view

/// Markdown renderer backed by WKWebView (markdown-it + KaTeX + highlight.js, GitHub styling).
/// Tapped links never leave the app — they are classified into `MarkdownLink` values and
/// handed to `onOpenLink`.
struct WebMarkdownView: View {
    let markdown: String
    /// Base URL for resolving relative image paths (raw.githubusercontent.com directory).
    var rawBaseURL: URL? = nil
    /// Base URL for resolving relative links (github.com blob directory).
    var blobBaseURL: URL? = nil
    /// Called when a link is tapped, enabling in-app navigation.
    var onOpenLink: ((MarkdownLink) -> Void)? = nil
    /// Downloads GitHub-hosted images natively (adds auth for private repositories).
    var imageLoader: MarkdownImageLoader? = nil
    /// Called with the rendered content height (points) whenever it changes —
    /// lets chat bubbles size the web view to fit.
    var onContentHeight: ((CGFloat) -> Void)? = nil
    /// When true the web view doesn't scroll itself and passes scroll events
    /// through to the enclosing scroll view (chat bubbles).
    var scrollPassthrough: Bool = false
    /// Base font size of the rendered content, in points.
    var fontSize: Int = 16

    var body: some View {
        WebViewRepresentable(markdown: markdown,
                             rawBaseURL: rawBaseURL,
                             blobBaseURL: blobBaseURL,
                             onOpenLink: onOpenLink,
                             imageLoader: imageLoader,
                             onContentHeight: onContentHeight,
                             scrollPassthrough: scrollPassthrough,
                             fontSize: fontSize)
    }
}

// MARK: - Cross-platform wrapper

/// Web view that can hand scroll-wheel events to the enclosing scroll view
/// instead of consuming them (chat bubbles sized to fit their content).
private final class PassthroughWebView: WKWebView {
    var scrollPassthrough = false

    #if canImport(AppKit)
    override func scrollWheel(with event: NSEvent) {
        if scrollPassthrough {
            nextResponder?.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }
    }
    #endif
}

private struct WebViewRepresentable {
    let markdown: String
    let rawBaseURL: URL?
    let blobBaseURL: URL?
    let onOpenLink: ((MarkdownLink) -> Void)?
    let imageLoader: MarkdownImageLoader?
    let onContentHeight: ((CGFloat) -> Void)?
    let scrollPassthrough: Bool
    let fontSize: Int

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let rawBaseURL: URL?
        let blobBaseURL: URL?
        let onOpenLink: ((MarkdownLink) -> Void)?
        let imageLoader: MarkdownImageLoader?
        let onContentHeight: ((CGFloat) -> Void)?

        var pageLoaded = false
        var lastRenderedMarkdown: String?
        var lastFontSize: Int?
        var pendingMarkdown: String?
        /// Latest font size passed from SwiftUI, used when the page finishes loading.
        var currentFontSize = 16
        weak var webView: WKWebView?

        init(rawBaseURL: URL?, blobBaseURL: URL?, onOpenLink: ((MarkdownLink) -> Void)?,
             imageLoader: MarkdownImageLoader?, onContentHeight: ((CGFloat) -> Void)?) {
            self.rawBaseURL = rawBaseURL
            self.blobBaseURL = blobBaseURL
            self.onOpenLink = onOpenLink
            self.imageLoader = imageLoader
            self.onContentHeight = onContentHeight
        }

        // MARK: Rendering

        func render(_ markdown: String, fontSize: Int, in webView: WKWebView) {
            guard pageLoaded else { return }
            if markdown != lastRenderedMarkdown {
                lastRenderedMarkdown = markdown
                let js = "renderMarkdown(\(Self.jsString(markdown)), \(Self.jsStringOrNull(rawBaseURL)), \(Self.jsStringOrNull(blobBaseURL)))"
                webView.evaluateJavaScript(js, completionHandler: nil)
            }
            if fontSize != lastFontSize {
                lastFontSize = fontSize
                webView.evaluateJavaScript("setFontSize(\(fontSize))", completionHandler: nil)
            }
        }

        private static func jsString(_ string: String) -> String {
            guard let data = try? JSONEncoder().encode(string),
                  let encoded = String(data: data, encoding: .utf8) else { return "\"\"" }
            return encoded
        }

        private static func jsStringOrNull(_ url: URL?) -> String {
            guard let url else { return "null" }
            return jsString(url.absoluteString)
        }

        // MARK: WKScriptMessageHandler (image loading)

        /// The page posts `[{index, url}]` for GitHub-hosted images; each is downloaded
        /// natively (with auth, so private repos work) and swapped in as a data URL.
        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            // Rendered content height reports (ResizeObserver in the page).
            if message.name == "contentHeight", let height = message.body as? Double {
                onContentHeight?(CGFloat(height))
                return
            }
            guard message.name == "loadImages",
                  let jobs = message.body as? [[String: Any]],
                  let imageLoader else { return }
            for job in jobs {
                guard let index = job["index"] as? Int,
                      let urlString = job["url"] as? String,
                      let url = URL(string: urlString) else { continue }
                Task { @MainActor [weak self] in
                    guard let self,
                          let result = try? await imageLoader(url),
                          let webView = self.webView else { return }
                    let dataURL = "data:\(result.mimeType);base64,\(result.data.base64EncodedString())"
                    webView.evaluateJavaScript(
                        "setImageData(\(index), \(Self.jsString(dataURL)))", completionHandler: nil)
                }
            }
        }

        // MARK: WKNavigationDelegate

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            pageLoaded = true
            if let markdown = pendingMarkdown {
                pendingMarkdown = nil
                render(markdown, fontSize: currentFontSize, in: webView)
            } else {
                render(lastRenderedMarkdown ?? "", fontSize: currentFontSize, in: webView)
            }
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            // Initial template load and in-page anchors (resolved against the local file URL).
            if url.isFileURL || url.scheme == "about" {
                decisionHandler(.allow)
                return
            }
            // Links into the repository the document belongs to → open in-app (any file type).
            if let blobBaseURL,
               url.absoluteString.hasPrefix(blobBaseURL.absoluteString) {
                let remainder = String(url.absoluteString.dropFirst(blobBaseURL.absoluteString.count))
                let pathPart = remainder.split(separator: "#").first.map(String.init) ?? remainder
                if !pathPart.isEmpty {
                    onOpenLink?(.sameRepoFile(path: pathPart.removingPercentEncoding ?? pathPart))
                }
                decisionHandler(.cancel)
                return
            }
            // Everything else http(s) → classify and route in-app. No system browser, ever.
            if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
                onOpenLink?(Self.route(url))
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.cancel)
        }

        /// Maps an external URL to an in-app navigation target.
        private static func route(_ url: URL) -> MarkdownLink {
            guard let host = url.host()?.lowercased() else { return .web(url) }
            let segments = url.pathComponents.filter { $0 != "/" }
            if host == "github.com" || host == "www.github.com" {
                guard segments.count >= 2 else { return .web(url) }
                let owner = segments[0]
                var name = segments[1]
                if name.hasSuffix(".git") { name = String(name.dropLast(4)) }
                // /{owner}/{repo}/blob/{ref}/{path...} → file view
                if segments.count >= 5, segments[2] == "blob" {
                    let ref = segments[3]
                    let path = segments.dropFirst(4).joined(separator: "/")
                    return .repoFile(RepoFileRef(owner: owner, repo: name, branch: ref, path: path))
                }
                // /{owner}/{repo}/tree/{ref}/{path...} → directory view (trailing
                // slash marks the directory for RepoFileRef.isDirectory)
                if segments.count >= 5, segments[2] == "tree" {
                    let ref = segments[3]
                    let path = segments.dropFirst(4).joined(separator: "/")
                    return .repoFile(RepoFileRef(owner: owner, repo: name, branch: ref, path: path + "/"))
                }
                return .repo(owner: owner, name: name)
            }
            // raw.githubusercontent.com/{owner}/{repo}/{ref}/{path...} → file view
            if host == "raw.githubusercontent.com", segments.count >= 4 {
                let path = segments.dropFirst(3).joined(separator: "/")
                return .repoFile(RepoFileRef(owner: segments[0], repo: segments[1],
                                             branch: segments[2], path: path))
            }
            return .web(url)
        }
    }

    @MainActor
    func makeWebView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "loadImages")
        configuration.userContentController.add(context.coordinator, name: "contentHeight")
        let webView = PassthroughWebView(frame: .zero, configuration: configuration)
        webView.scrollPassthrough = scrollPassthrough
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        #if canImport(UIKit)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        // Bubbles sized to fit must not trap scroll touches.
        webView.scrollView.isScrollEnabled = !scrollPassthrough
        #else
        webView.setValue(false, forKey: "drawsBackground")
        #endif
        if let dir = WebAssets.sharedDirectory {
            webView.loadFileURL(dir.appending(path: "template.html"), allowingReadAccessTo: dir)
        }
        return webView
    }

    @MainActor
    func update(webView: WKWebView, context: Context) {
        context.coordinator.currentFontSize = fontSize
        if context.coordinator.pageLoaded {
            context.coordinator.render(markdown, fontSize: fontSize, in: webView)
        } else {
            context.coordinator.pendingMarkdown = markdown
        }
    }
}

#if canImport(UIKit)
extension WebViewRepresentable: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator(rawBaseURL: rawBaseURL, blobBaseURL: blobBaseURL,
                    onOpenLink: onOpenLink, imageLoader: imageLoader,
                    onContentHeight: onContentHeight)
    }
    func makeUIView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateUIView(_ webView: WKWebView, context: Context) { update(webView: webView, context: context) }
}
#elseif canImport(AppKit)
extension WebViewRepresentable: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator(rawBaseURL: rawBaseURL, blobBaseURL: blobBaseURL,
                    onOpenLink: onOpenLink, imageLoader: imageLoader,
                    onContentHeight: onContentHeight)
    }
    func makeNSView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateNSView(_ webView: WKWebView, context: Context) { update(webView: webView, context: context) }
}
#endif

#Preview {
    WebMarkdownView(markdown: "# Hello\n\nMath $E=mc^2$\n\n```swift\nlet a = 1\n```\n")
}
