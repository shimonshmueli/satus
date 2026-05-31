// © Shimon Shmueli
#if SATUS_PRO
import Foundation

/// Anthropic Messages API implementation of `LLMClient`.
/// Reads the API key from Keychain on each call so a user can swap keys
/// without restarting the app.
struct AnthropicClient: LLMClient {

    static let defaultModel = "claude-haiku-4-5-20251001"

    private let model: String
    private let session: URLSession

    init(model: String = AnthropicClient.defaultModel,
         session: URLSession = .shared) {
        self.model = model
        self.session = session
    }

    func classify(tags: [TagDescriptor],
                  apps: [AppDescriptor]) async throws -> [Assignment] {
        guard let key = KeychainStore.load(for: .anthropic) else {
            throw LLMError.missingAPIKey
        }

        let payload = ClassifyInput(existingTags: tags, apps: apps)
        let payloadJSON: String
        do {
            let data = try JSONEncoder().encode(payload)
            payloadJSON = String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            throw LLMError.decoding("Failed to encode request: \(error.localizedDescription)")
        }

        let body = MessagesRequest(
            model: model,
            max_tokens: 8192,
            system: Self.systemPrompt,
            messages: [.init(role: "user", content: payloadJSON)]
        )

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue(key,          forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONEncoder().encode(body)

        // Retries on 429 with backoff; maps URL errors to friendly cases.
        let (data, http) = try await performWithRateLimitRetry(req, session: session)
        if let mapped = mapHTTPStatus(http, body: data) {
            throw mapped
        }

        // Anthropic returns: { content: [ { type: "text", text: "<json>" }, ... ], ... }
        let decoded: MessagesResponse
        do {
            decoded = try JSONDecoder().decode(MessagesResponse.self, from: data)
        } catch {
            throw LLMError.decoding("Top-level response: \(error.localizedDescription)")
        }
        guard let text = decoded.content.first(where: { $0.type == "text" })?.text else {
            throw LLMError.invalidResponse("No text block in response")
        }

        // The model is instructed to return strict JSON matching `ClassifyOutput`.
        // Strip code fences if it slipped any in despite instructions.
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

    // Kept intentionally short — the model's task is well-defined by the schema
    // and the user payload. Anything fancier belongs in v2 once we measure quality.
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

// MARK: - Wire types

// ClassifyInput / ClassifyOutput now live in LLMClient.swift so the tolerant
// per-element decoder is shared with the other providers.

private struct MessagesRequest: Codable {
    let model: String
    let max_tokens: Int
    let system: String
    let messages: [Message]
    struct Message: Codable {
        let role: String
        let content: String
    }
}

private struct MessagesResponse: Codable {
    let content: [Block]
    struct Block: Codable {
        let type: String
        let text: String?
    }
}
#endif
