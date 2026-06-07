// © Shimon Shmueli
import Foundation

/// Tiny per-backend disk cache for the Headless view. JSON file at
/// `~/Library/Application Support/ZoneKey/headless-cache.json`.
///
/// Stores merged `(list + outdated)` records keyed by backend ID with a
/// fetch timestamp. Default TTL is 1 hour — reads within the TTL skip the
/// shell call entirely; expired or missing entries trigger a fresh fetch.
struct HeadlessCache {

    static let defaultTTL: TimeInterval = 3600   // 1 hour

    /// Per-backend payload. `records` already has `latestVersion` merged in.
    struct Entry: Codable {
        let fetchedAt: Date
        let records: [PackageRecord]
    }

    /// On-disk envelope. `version` lets us evolve the schema later.
    private struct File: Codable {
        var version: Int
        var entries: [String: Entry]
    }

    private static let currentVersion = 1

    static let fileURL: URL = {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("ZoneKey", isDirectory: true)
        try? FileManager.default.createDirectory(at: support,
                                                 withIntermediateDirectories: true)
        return support.appendingPathComponent("headless-cache.json")
    }()

    // MARK: - Read

    /// Returns the cached entry for `backendID` if it's still within `ttl`.
    /// Returns nil on miss, expiry, decode failure, or version mismatch
    /// (so callers always fall back to fetching fresh).
    static func load(backendID: String,
                     ttl: TimeInterval = HeadlessCache.defaultTTL) -> Entry? {
        guard let data = try? Data(contentsOf: fileURL),
              let file = try? JSONDecoder().decode(File.self, from: data),
              file.version == currentVersion,
              let entry = file.entries[backendID]
        else { return nil }

        let age = Date().timeIntervalSince(entry.fetchedAt)
        return age <= ttl ? entry : nil
    }

    // MARK: - Write

    /// Upserts the entry for `backendID`. Other backends' entries are left
    /// untouched.
    static func save(backendID: String, records: [PackageRecord]) {
        var file = (try? JSONDecoder().decode(
            File.self, from: (try? Data(contentsOf: fileURL)) ?? Data()
        )) ?? File(version: currentVersion, entries: [:])

        if file.version != currentVersion {
            file = File(version: currentVersion, entries: [:])
        }
        file.entries[backendID] = Entry(fetchedAt: Date(), records: records)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(file) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// Clear a single backend's cached entry. Called by the explicit
    /// Refresh action so the next load forces a fetch.
    static func invalidate(backendID: String) {
        guard var file = try? JSONDecoder().decode(
            File.self, from: (try? Data(contentsOf: fileURL)) ?? Data()
        ) else { return }
        file.entries.removeValue(forKey: backendID)
        if let data = try? JSONEncoder().encode(file) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
