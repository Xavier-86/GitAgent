//
//  ChatStore.swift
//  GitAgent
//

import Foundation
import Observation

/// A persisted chat message.
struct ChatMessage: Codable, Identifiable {
    let id: UUID
    let role: String // "user" | "assistant"
    var content: String
    var reasoning: String
    /// @ / references attached by the user (shown as chips).
    var references: [ChatReference]
    /// The assembled prompt actually sent to the API (user messages with
    /// references); history falls back to `content` when nil.
    var prompt: String?

    init(role: String, content: String = "", reasoning: String = "",
         references: [ChatReference] = [], prompt: String? = nil) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.reasoning = reasoning
        self.references = references
        self.prompt = prompt
    }

    // Tolerant decoding so sessions persisted before references/prompt
    // existed still load.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(String.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        reasoning = try container.decodeIfPresent(String.self, forKey: .reasoning) ?? ""
        references = try container.decodeIfPresent([ChatReference].self, forKey: .references) ?? []
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt)
    }
}

/// A single conversation, persisted locally.
struct ChatSession: Codable, Identifiable {
    let id: UUID
    var title: String
    let createdAt: Date
    var messages: [ChatMessage]

    init(title: String = "") {
        self.id = UUID()
        self.title = title
        self.createdAt = Date()
        self.messages = []
    }

    init(id: UUID, title: String = "") {
        self.id = id
        self.title = title
        createdAt = Date()
        messages = []
    }
}

/// Multi-session chat history, persisted as JSON in Application Support.
@Observable
final class ChatStore {
    private(set) var sessions: [ChatSession] = []
    var currentID: ChatSession.ID?

    var current: ChatSession? {
        sessions.first { $0.id == currentID }
    }

    init() { load() }

    // MARK: - Sessions

    /// Returns the current session id, creating a session when none is active.
    @discardableResult
    func ensureCurrent() -> ChatSession.ID {
        if let currentID, sessions.contains(where: { $0.id == currentID }) {
            return currentID
        }
        let session = ChatSession()
        sessions.insert(session, at: 0)
        currentID = session.id
        save()
        return session.id
    }

    func newSession() {
        let session = ChatSession()
        sessions.insert(session, at: 0)
        currentID = session.id
        save()
    }

    func select(_ id: ChatSession.ID) {
        currentID = id
    }

    func ensureSession(_ id: ChatSession.ID) {
        guard !sessions.contains(where: { $0.id == id }) else { return }
        sessions.insert(ChatSession(id: id), at: 0)
        save()
    }

    func messages(for id: ChatSession.ID?) -> [ChatMessage] {
        guard let id else { return current?.messages ?? [] }
        return sessions.first { $0.id == id }?.messages ?? []
    }

    func append(_ message: ChatMessage, to id: ChatSession.ID?) {
        guard let id else { append(message); return }
        ensureSession(id)
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].messages.append(message)
        if sessions[index].title.isEmpty, message.role == "user" {
            sessions[index].title = String(message.content.prefix(40))
        }
        save()
    }

    func updateLast(in id: ChatSession.ID?, persist: Bool = true, _ transform: (inout ChatMessage) -> Void) {
        guard let id else { updateLast(persist: persist, transform); return }
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == id }),
              !sessions[sessionIndex].messages.isEmpty else { return }
        transform(&sessions[sessionIndex].messages[sessions[sessionIndex].messages.count - 1])
        if persist { save() }
    }

    func delete(_ id: ChatSession.ID) {
        sessions.removeAll { $0.id == id }
        if currentID == id { currentID = sessions.first?.id }
        save()
    }

    // MARK: - Messages

    func append(_ message: ChatMessage) {
        mutate { $0.messages.append(message) }
    }

    /// Mutates the last message. `persist: false` while streaming (a save per
    /// chunk would hammer the disk); call `persist()` when the stream ends.
    func updateLast(persist: Bool = true, _ transform: (inout ChatMessage) -> Void) {
        mutate(persist: persist) { session in
            guard !session.messages.isEmpty else { return }
            transform(&session.messages[session.messages.count - 1])
        }
    }

    func persist() { save() }

    private func mutate(persist: Bool = true, _ transform: (inout ChatSession) -> Void) {
        guard let index = sessions.firstIndex(where: { $0.id == currentID }) else { return }
        transform(&sessions[index])
        // Auto-title from the first user message.
        if sessions[index].title.isEmpty,
           let first = sessions[index].messages.first(where: { $0.role == "user" }) {
            sessions[index].title = String(first.content.prefix(30))
        }
        if persist { save() }
    }

    // MARK: - Persistence

    private var fileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: "GitAgent", directoryHint: .isDirectory)
            .appending(path: "chat-sessions.json")
    }

    private func save() {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(sessions).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("GitAgent: failed to save chat sessions \(error)")
        }
    }

    private func load() {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([ChatSession].self, from: data) else { return }
        sessions = decoded
        currentID = decoded.first?.id
    }
}
