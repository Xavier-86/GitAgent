//
//  TerminalView.swift
//  GitAgent
//
//  xterm.js terminal backed by WKWebView; bytes flow base64-encoded both ways.
//

import SwiftUI
import WebKit

/// Glue between a terminal session and the terminal web page. The owning view
/// wires `onInput`/`onResize` to the session and the session's output to
/// `write(_:)`.
@MainActor
@Observable
final class TerminalBridge {
    weak var webView: WKWebView?
    /// Keystrokes from the terminal page.
    var onInput: ((Data) -> Void)?
    /// Terminal geometry changes (cols, rows).
    var onResize: ((Int, Int) -> Void)?
    /// The page finished loading and is ready to receive output.
    var onReady: (() -> Void)?
    /// Applied when the page reports ready, and on every change.
    var fontSize = 13

    private var isReady = false
    private var pendingOutput = Data()

    func write(_ data: Data) {
        guard isReady, let webView else {
            pendingOutput.append(data)
            return
        }
        writeImmediately(data, to: webView)
    }

    /// Clears output from the previous shell without discarding bytes that
    /// arrive while a newly-created web view is still loading.
    func reset() {
        pendingOutput.removeAll(keepingCapacity: true)
        guard isReady else { return }
        webView?.evaluateJavaScript("resetTerminal()", completionHandler: nil)
    }

    func attach(_ webView: WKWebView) {
        self.webView = webView
        isReady = false
    }

    private func writeImmediately(_ data: Data, to webView: WKWebView) {
        let encoded = Self.jsString(data.base64EncodedString())
        webView.evaluateJavaScript("termWrite(\(encoded))", completionHandler: nil)
    }

    func setFontSize(_ size: Int) {
        fontSize = size
        webView?.evaluateJavaScript("setTermFontSize(\(size))", completionHandler: nil)
    }

    /// Re-fits the terminal and reports its size again even when unchanged —
    /// a session that connected after the page's initial fit never saw that
    /// resize event, so its PTY stayed at the default 80x24. Call this when
    /// a session reaches the connected state.
    func refitAndReportSize() {
        webView?.evaluateJavaScript("refit(); reportSize();", completionHandler: nil)
    }

    /// Called by the coordinator when the page signals `terminalReady`.
    func didBecomeReady() {
        isReady = true
        setFontSize(fontSize)
        onReady?()
        guard !pendingOutput.isEmpty, let webView else { return }
        let output = pendingOutput
        pendingOutput.removeAll(keepingCapacity: true)
        writeImmediately(output, to: webView)
    }

    static func jsString(_ string: String) -> String {
        guard let data = try? JSONEncoder().encode(string),
              let encoded = String(data: data, encoding: .utf8) else { return "\"\"" }
        return encoded
    }
}

struct TerminalView: View {
    let bridge: TerminalBridge
    var fontSize: Int = 13

    var body: some View {
        TerminalRepresentable(bridge: bridge)
            .background(.black)
            .onAppear { bridge.fontSize = fontSize }
            .onChange(of: fontSize) { _, newSize in bridge.setFontSize(newSize) }
    }
}

private struct TerminalRepresentable {
    let bridge: TerminalBridge

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler {
        let bridge: TerminalBridge

        init(bridge: TerminalBridge) { self.bridge = bridge }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            switch message.name {
            case "terminalInput":
                guard let base64 = message.body as? String,
                      let data = Data(base64Encoded: base64) else { return }
                bridge.onInput?(data)
            case "terminalResize":
                guard let body = message.body as? [String: Any],
                      let cols = body["cols"] as? Int,
                      let rows = body["rows"] as? Int else { return }
                bridge.onResize?(cols, rows)
            case "terminalReady":
                bridge.didBecomeReady()
            default:
                break
            }
        }
    }

    @MainActor
    func makeWebView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "terminalInput")
        configuration.userContentController.add(context.coordinator, name: "terminalResize")
        configuration.userContentController.add(context.coordinator, name: "terminalReady")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        bridge.attach(webView)
        #if canImport(UIKit)
        webView.isOpaque = true
        #endif
        if let dir = WebAssets.sharedDirectory {
            webView.loadFileURL(dir.appending(path: "terminal.html"), allowingReadAccessTo: dir)
        }
        return webView
    }
}

#if canImport(UIKit)
extension TerminalRepresentable: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator(bridge: bridge) }
    func makeUIView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateUIView(_ webView: WKWebView, context: Context) {}
}
#elseif canImport(AppKit)
extension TerminalRepresentable: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator(bridge: bridge) }
    func makeNSView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateNSView(_ webView: WKWebView, context: Context) {}
}
#endif
