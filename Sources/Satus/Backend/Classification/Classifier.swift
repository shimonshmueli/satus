// © Shimon Shmueli
#if SATUS_PRO
import Foundation
import CryptoKit

// MARK: - Validated output

/// What the rest of the app gets to see after validation: only real existing-tag
/// UUIDs survive, new-tag names are normalized, confidence is clamped to [0,1].
struct ValidatedAssignment: Codable, Hashable {
    let bundleID: String
    let existingTagIDs: [UUID]
    let newTagNames: [String]
    let rationale: String
    let confidence: Double
}

/// Summary of a single classifier run. Surfaced inline today; the review sheet
/// will consume `assignments` in the next milestone.
struct SuggestionRun {
    let assignments: [ValidatedAssignment]
    let cacheHits: Int
    let newRequests: Int
    let unknownTagIDsDropped: Int
    let newTagNamesDroppedOrNormalized: Int
}

// MARK: - Classifier

/// Orchestrates one classification run: filter via cache, call the LLM, validate
/// the reply, persist new entries to the cache. No state mutation on AppService.
struct Classifier {

    let client: LLMClient

    /// Maximum length for any new tag name. Long names are usually a sign the
    /// model went off-script; clip them rather than reject so the rest stays useful.
    static let maxNewTagNameLength = 30

    /// Apps per LLM request. Small enough that the JSON reply fits well under
    /// the 8192-token output cap even when every assignment has a rationale.
    static let appsPerBatch = 20

    func suggest(for apps: [AppItem],
                 existingTags: [AppTag]) async throws -> SuggestionRun {

        let currentHash = Self.tagSetHash(existingTags)
        var cache = ClassificationCache.load(currentTagSetHash: currentHash)

        // Split cached vs. needs-fetching.
        var cached: [ValidatedAssignment] = []
        var toFetch: [AppItem] = []
        for app in apps {
            let version = Self.appVersion(at: app.url) ?? "unknown"
            let key = Self.cacheKey(bundleID: app.id, version: version)
            if let hit = cache.entries[key] {
                cached.append(hit)
            } else {
                toFetch.append(app)
            }
        }

        var validatedNew: [ValidatedAssignment] = []
        var droppedIDs = 0
        var droppedNames = 0

        if !toFetch.isEmpty {
            let tagDescriptors = existingTags.map {
                TagDescriptor(id: $0.id.uuidString, name: $0.name)
            }
            // Index inputs once so we can look up versions per assignment.
            let appByID = Dictionary(uniqueKeysWithValues: toFetch.map { ($0.id, $0) })

            // Send in batches so the JSON reply stays under the model's output cap.
            // One bad batch fails the whole run; that's fine for v1, simpler than partial-apply.
            for batch in toFetch.chunked(into: Self.appsPerBatch) {
                let appDescriptors = batch.map {
                    AppDescriptor(bundleID: $0.id, name: $0.name, category: $0.category)
                }
                let raw = try await client.classify(tags: tagDescriptors, apps: appDescriptors)

                for assignment in raw {
                    let (v, di, dn) = Self.validate(assignment, existingTags: existingTags)
                    droppedIDs   += di
                    droppedNames += dn
                    validatedNew.append(v)

                    // Cache only if we recognize the bundleID; an unknown bundleID
                    // suggests the model hallucinated and we shouldn't poison the cache.
                    if let app = appByID[v.bundleID] {
                        let version = Self.appVersion(at: app.url) ?? "unknown"
                        cache.entries[Self.cacheKey(bundleID: app.id, version: version)] = v
                    }
                }
            }

            cache.save(currentTagSetHash: currentHash)
        }

        return SuggestionRun(
            assignments: cached + validatedNew,
            cacheHits: cached.count,
            newRequests: toFetch.count,
            unknownTagIDsDropped: droppedIDs,
            newTagNamesDroppedOrNormalized: droppedNames
        )
    }

    // MARK: - Validation

    /// Returns the validated assignment plus counts of (dropped existing IDs,
    /// dropped-or-normalized new tag names) for reporting.
    private static func validate(_ a: Assignment,
                                 existingTags: [AppTag])
    -> (ValidatedAssignment, droppedIDs: Int, droppedNames: Int) {

        let validIDs = Set(existingTags.map { $0.id })
        let existingNamesLower = Set(existingTags.map { $0.name.lowercased() })

        var droppedIDs = 0
        let cleanedIDs: [UUID] = a.existingTagIDs.compactMap { raw in
            guard let uuid = UUID(uuidString: raw), validIDs.contains(uuid) else {
                droppedIDs += 1
                return nil
            }
            return uuid
        }

        var droppedNames = 0
        var seenLower = Set<String>()
        let cleanedNames: [String] = a.newTagNames.compactMap { raw in
            let normalized = normalizeTagName(raw)
            guard !normalized.isEmpty else {
                droppedNames += 1
                return nil
            }
            let lower = normalized.lowercased()
            // Reject names that already exist or that the model proposed twice.
            if existingNamesLower.contains(lower) || seenLower.contains(lower) {
                droppedNames += 1
                return nil
            }
            seenLower.insert(lower)
            if normalized != raw { droppedNames += 1 }  // counted as "normalized"
            return normalized
        }

        let confidence = max(0.0, min(1.0, a.confidence))

        return (
            ValidatedAssignment(
                bundleID: a.bundleID,
                existingTagIDs: cleanedIDs,
                newTagNames: cleanedNames,
                rationale: a.rationale,
                confidence: confidence
            ),
            droppedIDs,
            droppedNames
        )
    }

    /// Allow letters, numbers, and ASCII spaces; collapse whitespace; clip length.
    /// Conservative on purpose — anything weirder we can relax later with evidence.
    private static func normalizeTagName(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.whitespaces)
        let filtered = String(raw.unicodeScalars.filter { allowed.contains($0) })
        let collapsed = filtered
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        let trimmed = collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(maxNewTagNameLength))
    }

    // MARK: - Hash / key helpers

    /// Stable SHA-256 over the sorted, lowercased tag-name set. Stable across
    /// launches (Swift's `hashValue` is not), so the cache survives relaunches
    /// when the tag set is unchanged.
    private static func tagSetHash(_ tags: [AppTag]) -> String {
        let joined = tags
            .map { $0.name.lowercased() }
            .sorted()
            .joined(separator: "\u{1F}")  // ASCII unit separator — won't collide with names
        let digest = SHA256.hash(data: Data(joined.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func cacheKey(bundleID: String, version: String) -> String {
        "\(bundleID)|\(version)"
    }

    private static func appVersion(at url: URL) -> String? {
        Bundle(url: url)?.infoDictionary?["CFBundleShortVersionString"] as? String
    }
}

// MARK: - On-disk cache

/// JSON file at ~/Library/Application Support/ZoneKey/classification-cache.json.
/// The whole file is invalidated when the tag set hash changes — simpler and
/// correct, since the model's prompt depends on the full tag set.
struct ClassificationCache {

    var entries: [String: ValidatedAssignment] = [:]

    private struct File: Codable {
        let version: Int
        let tagSetHash: String
        let entries: [String: ValidatedAssignment]
    }

    static let fileURL: URL = {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("ZoneKey", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("classification-cache.json")
    }()

    static func load(currentTagSetHash: String) -> ClassificationCache {
        guard let data = try? Data(contentsOf: fileURL),
              let file = try? JSONDecoder().decode(File.self, from: data),
              file.tagSetHash == currentTagSetHash
        else {
            return ClassificationCache()
        }
        var c = ClassificationCache()
        c.entries = file.entries
        return c
    }

    func save(currentTagSetHash: String) {
        let file = File(version: 1, tagSetHash: currentTagSetHash, entries: entries)
        if let data = try? JSONEncoder().encode(file) {
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }
}
#endif
