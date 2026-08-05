//
//  AppSettings.swift
//  GitAgent
//

import Foundation

/// App-wide settings, persisted in UserDefaults (API key in the Keychain).
@Observable
final class AppSettings {
    static let fontSizeKey = "fontSize"
    static let uiFontSizeKey = "uiFontSize"
    static let terminalFontSizeKey = "terminalFontSize"
    static let kimiBaseURLKey = "kimiBaseURL"
    static let kimiModelKey = "kimiModel"
    static let chatProviderKey = "chatProvider"
    static let coderToolKey = "coderTool"

    /// Base font size (points) for rendered Markdown content.
    var fontSize: Int {
        didSet { UserDefaults.standard.set(fontSize, forKey: Self.fontSizeKey) }
    }

    /// Base font size (points) for the app UI itself (lists, labels, buttons).
    var uiFontSize: Int {
        didSet { UserDefaults.standard.set(uiFontSize, forKey: Self.uiFontSizeKey) }
    }

    /// Font size (points) of the SSH terminal (xterm.js).
    var terminalFontSize: Int {
        didSet { UserDefaults.standard.set(terminalFontSize, forKey: Self.terminalFontSizeKey) }
    }

    /// Selected LLM provider. Switching providers resets the base URL and
    /// model to the provider's defaults (Custom keeps whatever is entered).
    var chatProvider: ChatProvider {
        didSet {
            UserDefaults.standard.set(chatProvider.rawValue, forKey: Self.chatProviderKey)
            if chatProvider != .custom {
                kimiBaseURL = chatProvider.defaultBaseURL
                kimiModel = chatProvider.defaultModel
            }
        }
    }

    /// Default coding CLI for new Coder agent tasks.
    var coderTool: CoderTool {
        didSet { UserDefaults.standard.set(coderTool.rawValue, forKey: Self.coderToolKey) }
    }

    /// API key for the selected provider, stored in the Keychain — never
    /// hardcoded, always user-entered.
    var kimiAPIKey: String {
        didSet {
            if kimiAPIKey.isEmpty {
                KeychainHelper.deleteKimiAPIKey()
            } else {
                KeychainHelper.save(kimiAPIKey: kimiAPIKey)
            }
        }
    }

    /// Base URL of the chat endpoint (auto-filled by the provider, editable).
    var kimiBaseURL: String {
        didSet { UserDefaults.standard.set(kimiBaseURL, forKey: Self.kimiBaseURLKey) }
    }

    /// Model identifier sent with each request.
    var kimiModel: String {
        didSet { UserDefaults.standard.set(kimiModel, forKey: Self.kimiModelKey) }
    }

    init() {
        let storedSize = UserDefaults.standard.integer(forKey: Self.fontSizeKey)
        fontSize = storedSize > 0 ? storedSize : 16
        let storedUISize = UserDefaults.standard.integer(forKey: Self.uiFontSizeKey)
        uiFontSize = storedUISize > 0 ? storedUISize : 16
        let storedTerminalSize = UserDefaults.standard.integer(forKey: Self.terminalFontSizeKey)
        terminalFontSize = storedTerminalSize > 0 ? storedTerminalSize : 13
        let storedProvider = UserDefaults.standard.string(forKey: Self.chatProviderKey) ?? ""
        chatProvider = ChatProvider(rawValue: storedProvider) ?? .kimiCode
        let storedCoderTool = UserDefaults.standard.string(forKey: Self.coderToolKey) ?? ""
        coderTool = CoderTool(rawValue: storedCoderTool) ?? .kimi
        kimiAPIKey = KeychainHelper.readKimiAPIKey() ?? ""
        kimiBaseURL = UserDefaults.standard.string(forKey: Self.kimiBaseURLKey)
            ?? ChatProvider.kimiCode.defaultBaseURL
        kimiModel = UserDefaults.standard.string(forKey: Self.kimiModelKey)
            ?? ChatProvider.kimiCode.defaultModel
    }

    /// A configured client, or nil when no API key has been entered.
    var chatClient: ChatClient? {
        guard !kimiAPIKey.isEmpty,
              let url = URL(string: kimiBaseURL) else { return nil }
        return ChatClient(apiKey: kimiAPIKey, baseURL: url, model: kimiModel,
                          format: chatProvider.format)
    }

    /// UI string for a key. The app UI is English-only.
    func tr(_ key: L10n.Key) -> String {
        L10n.resolveCurrent(key)
    }
}
