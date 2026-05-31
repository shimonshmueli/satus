// © Shimon Shmueli
#if SATUS_PRO
import Foundation

/// Local-model classifier using Ollama's OpenAI-compatible chat endpoint.
/// No API key required; the user supplies a host URL (default
/// `http://localhost:11434`) and a model identifier (e.g. `llama3.2`).
/// They must have the model pulled locally first via `ollama pull <model>`.
struct OllamaClient: LLMClient {

    static let defaultHost  = "http://localhost:11434"
    static let defaultModel = "llama3.2"

    private let host: String
    private let model: String
    private let session: URLSession

    init(host: String = OllamaClient.defaultHost,
         model: String = OllamaClient.defaultModel,
         session: URLSession = .shared) {

        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip trailing slash so the URL concatenation below stays predictable.
        let normalizedHost = trimmedHost.hasSuffix("/")
            ? String(trimmedHost.dropLast())
            : trimmedHost
        self.host = normalizedHost.isEmpty ? OllamaClient.defaultHost : normalizedHost

        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = trimmedModel.isEmpty ? OllamaClient.defaultModel : trimmedModel

        self.session = session
    }

    func classify(tags: [TagDescriptor],
                  apps: [AppDescriptor]) async throws -> [Assignment] {

        let userPayload: String
        do {
            let data = try JSONEncoder().encode(
                ClassifyInput(existingTags: tags, apps: apps)
            )
            userPayload = String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            throw LLMError.decoding("Failed to encode request: \(error.localizedDescription)")
        }

        // Ollama exposes an OpenAI-compatible chat completions endpoint.
        // Same request shape as OpenRouterClient minus the auth header.
        let body = ChatRequest(
            model: model,
            messages: [
                .init(role: "system", content: Self.systemPrompt),
                .init(role: "user",   content: userPayload)
            ],
            response_format: .init(type: "json_object")
        )

        guard let url = URL(string: "\(host)/v1/chat/completions") else {
            throw LLMError.invalidResponse("Invalid Ollama host: \(host)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        // Local model inference can be slow on first run while the model warms up.
        req.timeoutInterval = 120

        let (data, http) = try await performWithRateLimitRetry(req, session: session)
        if let mapped = mapHTTPStatus(http, body: data) {
            throw mapped
        }

        let decoded: ChatResponse
        do {
            decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        } catch {
            throw LLMError.decoding("Top-level response: \(error.localizedDescription)")
        }
        guard let text = decoded.choices.first?.message.content else {
            throw LLMError.invalidResponse("No choices/message.content in response")
        }

        let cleaned = Self.stripCodeFences(text)
        let result: ClassifyOutput
        do {
            result = try JSONDecoder().decode(ClassifyOutput.self,
                                              from: Data(cleaned.utf8))
        } catch {
            throw LLMError.decoding(diagnosticMessage(error: error, cleaned: cleaned, raw: text))
        }
        return result.assignments
    }

    // MARK: - Prompt

    // Same contract as the cloud providers. Kept duplicated so each provider
    // can tune wording independently if a local model needs hand-holding.
    private static let systemPrompt = """
    You classify macOS apps into the user's existing tags. The user will send a JSON \
    object with two fields: "existingTags" (an array of {id, name, description?}) \
    and "apps" (an array of {bundleID, name, category}).

    Pick from the existing tags only. NEVER invent new tag names. An app may belong \
    to multiple tags. Use the description (when present) to understand what each \
    tag covers.

    Reply with STRICT JSON only, no prose, no code fences, matching this schema:

    {
      "assignments": [
        {
          "bundleID": "string",
          "existingTagIDs": ["string", ...],
          "rationale": "one short sentence",
          "confidence": 0.0
        }
      ]
    }

    Rules:
    - confidence is a number between 0 and 1.
    - Use existing tag IDs verbatim from the input.
    - If no tag fits, return an empty existingTagIDs array and low confidence.
    """

    private static func stripCodeFences(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("```") {
            if let nl = t.firstIndex(of: "\n") { t = String(t[t.index(after: nl)...]) }
            if t.hasSuffix("```") { t = String(t.dropLast(3)) }
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Wire types (OpenAI Chat Completions shape)

// ClassifyInput / ClassifyOutput now live in LLMClient.swift so the tolerant
// per-element decoder is shared with the other providers.

private struct ChatRequest: Codable {
    let model: String
    let messages: [Message]
    let response_format: ResponseFormat?
    struct Message: Codable {
        let role: String
        let content: String
    }
    struct ResponseFormat: Codable {
        let type: String
    }
}

private struct ChatResponse: Codable {
    let choices: [Choice]
    struct Choice: Codable {
        let message: Message
    }
    struct Message: Codable {
        let content: String
    }
}
#endif
