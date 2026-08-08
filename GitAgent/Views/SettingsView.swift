//
//  SettingsView.swift
//  GitAgent
//

import SwiftUI

/// App settings (macOS: ⌘, window; iOS: gear button in the sidebar).
/// Reading font size and the AI chat provider configuration.
struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.isWorkspacePage) private var isWorkspacePage

    /// Models fetched from `{baseURL}/models` — the Model field becomes a
    /// picker when the endpoint responds, and stays a text field otherwise.
    @State private var availableModels: [String] = []
    @State private var isLoadingModels = false

    var body: some View {
        Form {
            Stepper(value: uiFontSizeBinding, in: 12...24) {
                HStack {
                    Text(settings.tr(.uiFontSize))
                    Spacer()
                    Text("\(settings.uiFontSize)")
                        .foregroundStyle(.secondary)
                }
            }
            Stepper(value: markdownFontSizeBinding, in: 12...24) {
                HStack {
                    Text(settings.tr(.markdownFontSize))
                    Spacer()
                    Text("\(settings.fontSize)")
                        .foregroundStyle(.secondary)
                }
            }
            Stepper(value: terminalFontSizeBinding, in: 9...24) {
                HStack {
                    Text(settings.tr(.terminalFontSize))
                    Spacer()
                    Text("\(settings.terminalFontSize)")
                        .foregroundStyle(.secondary)
                }
            }

            Section(settings.tr(.kimiSection)) {
                Picker(settings.tr(.provider), selection: Binding(
                    get: { settings.chatProvider },
                    set: { settings.chatProvider = $0 }
                )) {
                    ForEach(ChatProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                SecureField(settings.tr(.kimiAPIKey), text: Binding(
                    get: { settings.kimiAPIKey },
                    set: { settings.kimiAPIKey = $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                ))
                TextField(settings.tr(.kimiBaseURL), text: Binding(
                    get: { settings.kimiBaseURL },
                    set: { settings.kimiBaseURL = $0 }
                ))
                #if os(iOS)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                #endif

                if isLoadingModels {
                    HStack {
                        Text(settings.tr(.kimiModel))
                        Spacer()
                        ProgressView()
                    }
                } else if !availableModels.isEmpty {
                    Picker(settings.tr(.kimiModel), selection: Binding(
                        get: { settings.kimiModel },
                        set: { settings.kimiModel = $0 }
                    )) {
                        ForEach(modelOptions, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                } else {
                    TextField(settings.tr(.kimiModel), text: Binding(
                        get: { settings.kimiModel },
                        set: { settings.kimiModel = $0 }
                    ))
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                }

                Button {
                    Task { await fetchModels() }
                } label: {
                    Label(settings.tr(.refreshModels), systemImage: "arrow.clockwise")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(settings.tr(.settings))
        #if os(macOS)
        .frame(width: isWorkspacePage ? nil : 360)
        .frame(
            maxWidth: isWorkspacePage ? 720 : nil,
            maxHeight: isWorkspacePage ? .infinity : nil,
            alignment: .top
        )
        .padding()
        #endif
        .task(id: settings.chatProvider) { await fetchModels() }
    }

    /// Fetched models, plus the currently configured one if the endpoint
    /// didn't list it (so the picker never loses the selection).
    private var modelOptions: [String] {
        if availableModels.contains(settings.kimiModel) || settings.kimiModel.isEmpty {
            return availableModels
        }
        return [settings.kimiModel] + availableModels
    }

    private func fetchModels() async {
        guard !settings.kimiAPIKey.isEmpty,
              let baseURL = URL(string: settings.kimiBaseURL) else {
            availableModels = []
            return
        }
        isLoadingModels = true
        defer { isLoadingModels = false }
        guard let models = try? await ChatClient.fetchModels(
            apiKey: settings.kimiAPIKey, baseURL: baseURL,
            format: settings.chatProvider.format) else { return }
        availableModels = models
        if settings.kimiModel.isEmpty, let first = models.first {
            settings.kimiModel = first
        }
    }

    private var uiFontSizeBinding: Binding<Int> {
        Binding(
            get: { settings.uiFontSize },
            set: { settings.uiFontSize = $0 }
        )
    }

    private var markdownFontSizeBinding: Binding<Int> {
        Binding(
            get: { settings.fontSize },
            set: { settings.fontSize = $0 }
        )
    }

    private var terminalFontSizeBinding: Binding<Int> {
        Binding(
            get: { settings.terminalFontSize },
            set: { settings.terminalFontSize = $0 }
        )
    }
}

#Preview {
    SettingsView()
        .environment(AppSettings())
}
