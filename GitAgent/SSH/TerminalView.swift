//
//  TerminalView.swift
//  GitAgent
//
//  xterm.js terminal backed by WKWebView; bytes flow base64-encoded both ways.
//

import SwiftUI
import WebKit

/// Glue between the SSH session and the terminal web page. The owning view
/// wires `onInput`/`onResize` to the session and the session's output to
/// `write(_:)`.
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

    func write(_ data: Data) {
        guard let webView else { return }
        let encoded = Self.jsString(data.base64EncodedString())
        webView.evaluateJavaScript("termWrite(\(encoded))", completionHandler: nil)
    }

    func setFontSize(_ size: Int) {
        fontSize = size
        webView?.evaluateJavaScript("setTermFontSize(\(size))", completionHandler: nil)
    }

    /// Called by the coordinator when the page signals `terminalReady`.
    func didBecomeReady() {
        setFontSize(fontSize)
        onReady?()
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
            .background(Color(red: 0x1e / 255, green: 0x1e / 255, blue: 0x1e / 255))
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
        bridge.webView = webView
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
