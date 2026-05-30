// © Shimon Shmueli
#if SATUS_PRO
import Foundation

// MARK: - Wire DTOs

/// One of the user's existing tags, as the model sees it.
struct TagDescriptor: Codable, Hashable {
    let id: String   // UUID string
    let name: String
}

/// One app to classify.
struct AppDescriptor: Codable, Hashable {
    let bundleID: String
    let name: String
    let category: String?  // LSApplicationCategoryType, e.g. "public.app-category.developer-tools"
}

/// The model's proposed assignment for a single app.
/// Nothing here is applied until the user approves it in the review sheet.
struct Assignment: Codable, Hashable {
    let bundleID: String
    let existingTagIDs: [String]
    let newTagNames: [String]
    let rationale: String
    let confidence: Double
}

// MARK: - Errors

enum LLMError: LocalizedError {
    case missingAPIKey
    case invalidResponse(String)
    case http(status: Int, body: String)
    case decoding(String)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:           return "No API key stored for this provider."
        case .invalidResponse(let s):  return "Invalid model response: \(s)"
        case .http(let code, let b):   return "HTTP \(code): \(b.prefix(200))"
        case .decoding(let s):         return "Decoding error: \(s)"
        case .transport(let e):        return "Network error: \(e.localizedDescription)"
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
#endif
