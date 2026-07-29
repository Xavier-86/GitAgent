//
//  ChatView.swift
//  GitAgent
//

import SwiftUI

/// Kimi chat with multiple locally persisted sessions and @ / repository
/// references — the entry point for upcoming agent features.
struct ChatView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(GitHubAuthManager.self) private var auth
    @Environment(ChatStore.self) private var store

    @State private var isStreaming = false
    @State private var streamTask: Task<Void, Never>?
    @State private var showSessions = false

    private var messages: [ChatMessage] { store.current?.messages ?? [] }

    private var navigationTitle: String {
        if let title = store.current?.title, !title.isEmpty { return title }
        return settings.tr(.chat)
    }

    var body: some View {
        VStack(spacing: 0) {
            if settings.chatClient == nil {
                ContentUnavailableView(settings.tr(.agentNeedKey), systemImage: "key")
            } else if messages.isEmpty {
                emptyGuide
                ChatComposer(isStreaming: isStreaming, onSend: send, onStop: stop)
            } else {
                messageList
                ChatComposer(isStreaming: isStreaming, onSend: send, onStop: stop)
            }
        }
        .navigationTitle(navigationTitle)
        .fontSizeShortcuts(get: { settings.fontSize }, set: { settings.fontSize = $0 })
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 16) {
                    Button { showSessions = true } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    Button { store.newSession() } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
        }
        .sheet(isPresented: $showSessions) {
            SessionsView()
        }
        .onDisappear { streamTask?.cancel() }
    }

    /// First-launch guide: explains the @ / reference syntax.
    private var emptyGuide: some View {
        ContentUnavailableView {
            Label(settings.tr(.chatEmpty), systemImage: "text.bubble")
        } description: {
            VStack(alignment: .leading, spacing: 8) {
                Label(settings.tr(.chatGuideAt), systemImage: "at")
                Label(settings.tr(.chatGuideSlash), systemImage: "folder")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Message list

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(messages) { message in
                        messageBubble(message)
                            .id(message.id)
                    }
                }
                .padding()
            }
            .onChange(of: messages.last?.content) { _, _ in
                if let last = messages.last {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func messageBubble(_ message: ChatMessage) -> some View {
        let isUser = message.role == "user"
        HStack {
            if isUser { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 6) {
                if !message.references.isEmpty {
                    // Attached @ / references shown as chips above the text.
                    HStack(spacing: 4) {
                        ForEach(message.references) { reference in
                            Label(reference.displayName, systemImage: reference.icon)
                                .font(.system(size: CGFloat(settings.uiFontSize) - 4))
                                .lineLimit(1)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15), in: Capsule())
                        }
                    }
                }
                if !message.reasoning.isEmpty {
                    Text(message.reasoning)
                        .font(.system(size: CGFloat(settings.uiFontSize) - 4))
                        .foregroundStyle(.secondary)
                }
                if isUser {
                    // User text stays plain (keeps @ / mentions verbatim).
                    Text(message.content)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if message.content.isEmpty && isStreaming {
                    Text("…")
                } else {
                    // Assistant answers render as Markdown.
                    MarkdownBubbleView(markdown: message.content,
                                       fontSize: settings.fontSize)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isUser ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 12))
            if !isUser { Spacer(minLength: 40) }
        }
    }

    // MARK: - Sending

    private func send(text: String, references: [ChatReference]) {
        guard let client = settings.chatClient, !isStreaming else { return }
        isStreaming = true

        streamTask = Task { @MainActor in
            defer { isStreaming = false }
            // Assemble the prompt: user text first, referenced content after.
            let prompt = await PromptBuilder.build(text: text, references: references,
                                                   client: auth.client)
            store.ensureCurrent()
            store.append(ChatMessage(role: "user", content: text,
                                     references: references,
                                     prompt: prompt == text ? nil : prompt))
            store.append(ChatMessage(role: "assistant"))

            let history = messages.dropLast().map {
                ChatRequestMessage(role: $0.role, content: $0.prompt ?? $0.content)
            }
            do {
                // Throttle UI updates: flush accumulated deltas ~12x/s instead
                // of re-rendering the whole list + web view on every token.
                var pendingContent = ""
                var pendingReasoning = ""
                var lastFlush = Date.distantPast
                func flush() {
                    guard !pendingContent.isEmpty || !pendingReasoning.isEmpty else { return }
                    let content = pendingContent, reasoning = pendingReasoning
                    pendingContent = ""
                    pendingReasoning = ""
                    store.updateLast(persist: false) { message in
                        message.reasoning += reasoning
                        message.content += content
                    }
                    lastFlush = Date()
                }
                for try await delta in client.streamChat(messages: history) {
                    if let reasoning = delta.reasoning { pendingReasoning += reasoning }
                    if let content = delta.content { pendingContent += content }
                    if Date().timeIntervalSince(lastFlush) > 0.08 { flush() }
                }
                flush()
                store.persist()
            } catch {
                guard !Task.isCancelled else { return }
                store.updateLast { message in
                    let prefix = message.content.isEmpty ? "" : "\n\n"
                    message.content +=
                        "\(prefix)[\(settings.tr(.agentError))] \(error.localizedDescription)"
                }
            }
        }
    }

    private func stop() {
        streamTask?.cancel()
    }
}

/// Session history — tap to switch, swipe to delete.
private struct SessionsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ChatStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.sessions) { session in
                    Button {
                        store.select(session.id)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.title.isEmpty ? settings.tr(.newChat) : session.title)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text("\(session.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(session.messages.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    // iOS: swipe-to-delete (onDelete below) or long-press;
                    // macOS: right-click — both get this menu.
                    .contextMenu {
                        Button(role: .destructive) {
                            store.delete(session.id)
                        } label: {
                            Label(settings.tr(.delete), systemImage: "trash")
                        }
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        store.delete(store.sessions[index].id)
                    }
                }
            }
            .navigationTitle(settings.tr(.chats))
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
        .frame(minWidth: 360, minHeight: 400)
        #endif
    }
}

#Preview {
    NavigationStack {
        ChatView()
            .environment(AppSettings())
            .environment(GitHubAuthManager())
            .environment(ChatStore())
    }
}
