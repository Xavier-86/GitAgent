//
//  WebPageView.swift
//  GitAgent
//

import SwiftUI
import WebKit

/// Identifiable URL wrapper so a web page can be presented with `.sheet(item:)`.
struct IdentifiableURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// In-app web page shown in a sheet. Used for the OAuth authorization page and
/// for external links tapped inside rendered Markdown — nothing ever leaves the app.
struct WebPageView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    let url: URL

    var body: some View {
        NavigationStack {
            EmbeddedWebView(url: url)
                .navigationTitle(url.host() ?? url.absoluteString)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(settings.tr(.done)) { dismiss() }
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 640)
        #endif
    }
}

// MARK: - Cross-platform wrapper

/// Plain WKWebView that loads a URL and follows navigations in-place.
private struct EmbeddedWebView {
    let url: URL

    func makeWebView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.load(URLRequest(url: url))
        return webView
    }

    func update(webView: WKWebView, context: Context) {}
}

#if canImport(UIKit)
extension EmbeddedWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateUIView(_ webView: WKWebView, context: Context) { update(webView: webView, context: context) }
}
#elseif canImport(AppKit)
extension EmbeddedWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateNSView(_ webView: WKWebView, context: Context) { update(webView: webView, context: context) }
}
#endif

#Preview {
    WebPageView(url: URL(string: "https://github.com/login/device")!)
        .environment(AppSettings())
}
