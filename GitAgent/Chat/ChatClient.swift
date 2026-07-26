//
//  ChatClient.swift
//  GitAgent
//

import Foundation

/// Supported LLM providers. All except Anthropic speak the OpenAI Chat
/// Completions protocol; Anthropic uses its own Messages API.
enum ChatProvider: String, CaseIterable, Identifiable, Codable {
    case kimiCode, moonshot, openai, deepseek, anthropic, custom

    var id: Self { self }

    var displayName: String {
        switch self {
        case .kimiCode: return "Kimi Code"
        case .moonshot: return "Moonshot AI"
        case .openai: return "OpenAI"
        case .deepseek: return "DeepSeek"
        case .anthropic: return "Anthropic"
        case .custom: return "Custom"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .kimiCode: return "https://api.kimi.com/coding/v1"
        case .moonshot: return "https://api.moonshot.cn/v1"
        case .openai: return "https://api.openai.com/v1"
        case .deepseek: return "https://api.deepseek.com/v1"
        case .anthropic: return "https://api.anthropic.com/v1"
        case .custom: return ""
        }
    }

    var defaultModel: String {
        switch self {
        case .kimiCode: return "k3"
        case .moonshot: return "kimi-k2-0711-preview"
        case .openai: return "gpt-4o"
        case .deepseek: return "deepseek-chat"
        case .anthropic: return "claude-sonnet-4-5"
        case .custom: return ""
        }
    }

    var format: WireFormat {
        self == .anthropic ? .anthropic : .openAI
    }

    enum WireFormat {
        case openAI, anthropic
    }
}

/// A single chat message (OpenAI-compatible format; also maps 1:1 onto the
/// Anthropic Messages format for user/assistant roles).
struct ChatRequestMessage: Codable {
    let role: String
    let content: String
}

/// One streamed chunk from the model — new text and/or new reasoning text.
struct KimiDelta {
    var content: String?
    var reasoning: String?
}

/// Streaming chat client for OpenAI-compatible endpoints and the Anthropic
/// Messages API. Base URL, model and wire format come from settings, so
/// third-party OpenAI-compatible APIs work via the Custom provider.
final class ChatClient {
    let apiKey: String
    let baseURL: URL
    let model: String
    let format: ChatProvider.WireFormat

    init(apiKey: String, baseURL: URL, model: String, format: ChatProvider.WireFormat) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.model = model
        self.format = format
    }

    enum ChatError: LocalizedError {
        case httpError(status: Int, message: String)

        var errorDescription: String? {
            switch self {
            case .httpError(let status, let message):
                return "Chat request failed (\(status)): \(message)"
            }
        }
    }

    /// Streams a chat completion as a sequence of deltas. Reasoning models
    /// emit `reasoning` text before the final `content`.
    func streamChat(messages: [ChatRequestMessage]) -> AsyncThrowingStream<KimiDelta, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try makeRequest(messages: messages)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                        var body = ""
                        for try await line in bytes.lines { body += line }
                        let message = (try? JSONDecoder().decode(ErrorEnvelope.self, from: Data(body.utf8)))?.error.message ?? body
                        throw ChatError.httpError(status: http.statusCode, message: message)
                    }

                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8) else { continue }
                        switch format {
                        case .openAI:
                            guard let chunk = try? JSONDecoder().decode(OpenAIChunk.self, from: data),
                                  let delta = chunk.choices.first?.delta else { continue }
                            continuation.yield(KimiDelta(content: delta.content,
                                                         reasoning: delta.reasoningContent))
                        case .anthropic:
                            guard let event = try? JSONDecoder().decode(AnthropicEvent.self, from: data),
                                  let delta = event.delta else { continue }
                            switch delta.type {
                            case "text_delta":
                                continuation.yield(KimiDelta(content: delta.text))
                            case "thinking_delta":
                                continuation.yield(KimiDelta(reasoning: delta.thinking))
                            default:
                                continue
                            }
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Requests

    private func makeRequest(messages: [ChatRequestMessage]) throws -> URLRequest {
        switch format {
        case .openAI:
            var request = URLRequest(url: baseURL.appending(path: "chat/completions"))
            request.httpMethod = "POST"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 300
            request.httpBody = try JSONEncoder().encode(OpenAIRequest(
                model: model, messages: messages, stream: true))
            return request
        case .anthropic:
            var request = URLRequest(url: baseURL.appending(path: "messages"))
            request.httpMethod = "POST"
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 300
            request.httpBody = try JSONEncoder().encode(AnthropicRequest(
                model: model, messages: messages, maxTokens: 8192, stream: true))
            return request
        }
    }

    // MARK: - Wire format

    private struct OpenAIRequest: Encodable {
        let model: String
        let messages: [ChatRequestMessage]
        let stream: Bool
    }

    private struct OpenAIChunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                let content: String?
                let reasoningContent: String?

                enum CodingKeys: String, CodingKey {
                    case content
                    case reasoningContent = "reasoning_content"
                }
            }
            let delta: Delta
        }
        let choices: [Choice]
    }

    private struct AnthropicRequest: Encodable {
        let model: String
        let messages: [ChatRequestMessage]
        let maxTokens: Int
        let stream: Bool

        enum CodingKeys: String, CodingKey {
            case model, messages, stream
            case maxTokens = "max_tokens"
        }
    }

    private struct AnthropicEvent: Decodable {
        struct Delta: Decodable {
            let type: String?
            let text: String?
            let thinking: String?
        }
        let type: String?
        let delta: Delta?
    }

    // MARK: - Model listing

    /// Fetches the available model ids from `{baseURL}/models`. Both the
    /// OpenAI and Anthropic endpoints return `{data: [{id: …}]}`.
    static func fetchModels(apiKey: String, baseURL: URL,
                            format: ChatProvider.WireFormat) async throws -> [String] {
        var request = URLRequest(url: baseURL.appending(path: "models"))
        switch format {
        case .openAI:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case .anthropic:
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let message = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data))?.error.message ?? ""
            throw ChatError.httpError(status: status, message: message)
        }
        let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
        return decoded.data.map(\.id)
    }

    private struct ModelsResponse: Decodable {
        struct Model: Decodable { let id: String }
        let data: [Model]
    }

    private struct ErrorEnvelope: Decodable {
        struct ErrorBody: Decodable { let message: String }
        let error: ErrorBody
    }
}
