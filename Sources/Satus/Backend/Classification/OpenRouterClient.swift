// © Shimon Shmueli
#if SATUS_PRO
import Foundation

/// OpenRouter implementation of `LLMClient`. OpenRouter speaks the OpenAI
/// Chat Completions shape, so the wire types are OpenAI-style. The user
/// chooses the model in Settings; we don't hard-code anything beyond a default.
struct OpenRouterClient: LLMClient {

    static let defaultModel = "anthropic/claude-haiku-4-5"

    private let model: String
    private let session: URLSession

    init(model: String = OpenRouterClient.defaultModel,
         session: URLSession = .shared) {
        // Empty model string → fall back to default, so a blank Settings field
        // never produces a malformed request.
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = trimmed.isEmpty ? OpenRouterClient.defaultModel : trimmed
        self.session = session
    }

    func classify(tags: [TagDescriptor],
                  apps: [AppDescriptor]) async throws -> [Assignment] {
        guard let key = KeychainStore.load(for: .openrouter) else {
            throw LLMError.missingAPIKey
        }

        let userPayload: String
        do {
            let data = try JSONEncoder().encode(
                ClassifyInput(existingTags: tags, apps: apps)
            )
            userPayload = String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            throw LLMError.decoding("Failed to encode request: \(error.localizedDescription)")
        }

        let body = ChatRequest(
            model: model,
            messages: [
                .init(role: "system", content: Self.systemPrompt),
                .init(role: "user",   content: userPayload)
            ],
            // OpenAI-style JSON-mode hint. Most popular models on OpenRouter honor it;
            // models that don't will still get the system-prompt instruction.
            response_format: .init(type: "json_object"),
            // Generous cap — without this many models default to 1024 tokens
            // and silently truncate multi-app JSON output mid-string.
            max_tokens: 8192
        )

        var req = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)",     forHTTPHeaderField: "Authorization")
        req.setValue("application/json",  forHTTPHeaderField: "Content-Type")
        // Optional OpenRouter attribution headers — courteous, not required.
        req.setValue("https://github.com/shimonshmueli/satus", forHTTPHeaderField: "HTTP-Referer")
        req.setValue("ZoneKey",                                 forHTTPHeaderField: "X-Title")
        req.httpBody = try JSONEncoder().encode(body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw LLMError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse("Not an HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LLMError.http(status: http.statusCode, body: body)
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

    // Same contract as AnthropicClient; kept duplicated for now so each provider
    // can tune wording independently later without coupling.
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

private struct ClassifyInput: Codable {
    let existingTags: [TagDescriptor]
    let apps: [AppDescriptor]
}

private struct ClassifyOutput: Codable {
    let assignments: [Assignment]
}

private struct ChatRequest: Codable {
    let model: String
    let messages: [Message]
    let response_format: ResponseFormat?
    let max_tokens: Int?
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
