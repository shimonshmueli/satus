// © Shimon Shmueli
#if SATUS_PRO
import Foundation

// MARK: - Wire DTOs

/// One of the user's existing tags, as the model sees it. `description` is
/// non-nil only for tags whose name still matches a default-seed name — that
/// way renamed seeds drop their description (their meaning may have shifted).
struct TagDescriptor: Codable, Hashable {
    let id: String   // UUID string
    let name: String
    let description: String?
}

/// One app to classify.
struct AppDescriptor: Codable, Hashable {
    let bundleID: String
    let name: String
    let category: String?  // LSApplicationCategoryType, e.g. "public.app-category.developer-tools"
}

/// The model's proposed assignment for a single app. Existing-tags-only:
/// the prompt forbids the model from inventing new tag names. Nothing here
/// is applied until the user approves it in the review sheet.
struct Assignment: Codable, Hashable {
    let bundleID: String
    let existingTagIDs: [String]
    let rationale: String
    let confidence: Double
}

// MARK: - Errors

enum LLMError: LocalizedError {
    case missingAPIKey
    case invalidResponse(String)
    case unauthorized                          // HTTP 401 / 403
    case modelNotFound(String)                 // HTTP 404 (usually model name typo on OpenRouter)
    case rateLimited(retriesExhausted: Int)    // HTTP 429 after backoff retries
    case http(status: Int, body: String)
    case decoding(String)
    case notConnected                          // URLError offline / connection lost
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No API key stored for this provider."
        case .invalidResponse(let s):
            return "Invalid model response: \(s)"
        case .unauthorized:
            return "API key rejected. Check the key in Settings."
        case .modelNotFound(let body):
            return "Model not found. Check the model name in Settings. Provider said: \(body.prefix(200))"
        case .rateLimited(let n):
            return "Rate limited by provider after \(n) retries. Try again in a minute."
        case .http(let code, let b):
            return "HTTP \(code): \(b.prefix(200))"
        case .decoding(let s):
            return "Decoding error: \(s)"
        case .notConnected:
            return "No internet connection."
        case .transport(let e):
            return "Network error: \(e.localizedDescription)"
        }
    }
}

// MARK: - Protocol

/// Provider-agnostic interface. One call in, one batch of assignments out.
/// Implementations are responsible for prompt construction, the HTTP call,
/// and turning the model's reply into validated `Assignment` values.
protocol LLMClient {
    func classify(tags: [TagDescriptor],
                  apps: [AppDescriptor]) async throws -> [Assignment]
}

// MARK: - HTTP helpers (shared by both providers)

/// Performs the request, transparently retrying on HTTP 429 with backoff.
/// Honors `Retry-After` (seconds) when present, capped at 30s to avoid
/// pathological waits. Network errors are mapped to friendly `LLMError`s.
func performWithRateLimitRetry(
    _ request: URLRequest,
    session: URLSession,
    maxRetries: Int = 3
) async throws -> (Data, HTTPURLResponse) {

    var attempt = 0
    while true {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw mapTransportError(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse("Not an HTTP response")
        }

        if http.statusCode == 429 {
            if attempt >= maxRetries {
                throw LLMError.rateLimited(retriesExhausted: maxRetries)
            }
            let seconds = parseRetryAfter(http) ?? backoffSeconds(attempt: attempt)
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            attempt += 1
            continue
        }

        return (data, http)
    }
}

/// Translates the common non-2xx codes into friendly `LLMError` values.
/// Returns nil for 2xx — caller proceeds to decode the body.
func mapHTTPStatus(_ response: HTTPURLResponse, body: Data) -> LLMError? {
    if (200..<300).contains(response.statusCode) { return nil }
    let bodyString = String(data: body, encoding: .utf8) ?? ""
    switch response.statusCode {
    case 401, 403: return .unauthorized
    case 404:      return .modelNotFound(bodyString)
    default:       return .http(status: response.statusCode, body: bodyString)
    }
}

/// 2s, 4s, 8s — exponential with a hard cap to keep the user's wait bounded.
private func backoffSeconds(attempt: Int) -> Double {
    let base = pow(2.0, Double(attempt + 1))
    return min(8.0, base)
}

/// Parses the `Retry-After` header, accepting a delta-seconds integer.
/// Ignores HTTP-date form for simplicity — providers we care about send seconds.
private func parseRetryAfter(_ response: HTTPURLResponse) -> Double? {
    guard let header = response.value(forHTTPHeaderField: "Retry-After"),
          let seconds = Double(header.trimmingCharacters(in: .whitespaces))
    else { return nil }
    return min(seconds, 30.0)
}

private func mapTransportError(_ error: Error) -> LLMError {
    if let urlError = error as? URLError {
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .dnsLookupFailed:
            return .notConnected
        default:
            return .transport(error)
        }
    }
    return .transport(error)
}

// MARK: - Shared diagnostic

/// Builds the "Inner JSON failed to decode" message both providers throw.
/// Shows head + tail of the raw text and flags likely truncation so the user
/// can tell at a glance whether the model ran out of tokens.
func diagnosticMessage(error: Error, cleaned: String, raw: String) -> String {
    let endsCleanly = cleaned.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("}")
    let truncationHint = endsCleanly
        ? "Output appears complete."
        : "Looks truncated (no closing brace) — try raising max_tokens or splitting into smaller batches."
    let headLimit = 800
    let tailLimit = 300
    let head = String(raw.prefix(headLimit))
    let tail = raw.count > headLimit + tailLimit
        ? "\n…\n" + String(raw.suffix(tailLimit))
        : ""
    return """
    Inner JSON: \(error.localizedDescription)
    \(truncationHint)
    Raw head: \(head)\(tail)
    """
}
#endif
