// © Shimon Shmueli
import Foundation
import Security

/// Stores BYOK API keys for LLM providers in the macOS Keychain.
/// One slot per provider (anthropic, openrouter). Generic infrastructure;
/// compiles into both Free and Pro builds even though only Pro can use it.
enum KeychainStore {

    enum Provider: String, CaseIterable, Identifiable, Codable {
        case anthropic
        case openrouter
        case ollama   // Local — does not use Keychain; configured by host + model.

        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .anthropic:  return "Anthropic"
            case .openrouter: return "OpenRouter"
            case .ollama:     return "Ollama (local)"
            }
        }

        /// Ollama is local-only and does not require a stored API key.
        var requiresAPIKey: Bool {
            self != .ollama
        }
    }

    // Distinct service string per provider so accounts can't collide.
    private static let serviceBase = "com.zonekey.llm-key"
    private static func service(for provider: Provider) -> String {
        "\(serviceBase).\(provider.rawValue)"
    }

    // MARK: - API

    /// Saves or replaces the API key for the given provider. Empty string deletes.
    @discardableResult
    static func save(_ key: String, for provider: Provider) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return delete(for: provider) }

        guard let data = trimmed.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service(for: provider),
            kSecAttrAccount as String: provider.rawValue
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
        }
        return false
    }

    /// Returns the stored key for the provider, or nil if none.
    static func load(for provider: Provider) -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service(for: provider),
            kSecAttrAccount as String: provider.rawValue,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8)
        else { return nil }
        return string
    }

    /// Deletes the stored key for the provider. Returns true if removed or already absent.
    @discardableResult
    static func delete(for provider: Provider) -> Bool {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service(for: provider),
            kSecAttrAccount as String: provider.rawValue
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Convenience: does a key exist for this provider?
    static func hasKey(for provider: Provider) -> Bool {
        load(for: provider) != nil
    }
}
