// © Shimon Shmueli
import Foundation

/// Raw pip packages from the active Python environment. Less curated than
/// pipx — usually shows a long mix of user-installed tools and transitive
/// libraries — but it's where many CLI Python tools actually live.
///
/// Probes brew-installed pip3 first, then Apple's system pip3 as a fallback.
/// We don't reach into venvs in v1.
struct PipBackend: PackageManager {

    static let backendID   = "pip"
    static let displayName = "pip"
    static let sfSymbol    = "shippingbox"

    private let pipPath: String?

    init() {
        self.pipPath = Shell.findBinary(candidates: [
            "/opt/homebrew/bin/pip3",
            "/usr/local/bin/pip3",
            "/usr/bin/pip3"   // Apple-shipped pip3, deprecation-warning-prone
        ])
    }

    var isAvailable: Bool { pipPath != nil }

    func list() async throws -> [PackageRecord] {
        guard let pip = pipPath else { return [] }
        // --format=json gives a stable schema. --disable-pip-version-check
        // suppresses pip's own self-update nag on stderr.
        let output = try await Shell.run(
            pip,
            ["list", "--format=json", "--disable-pip-version-check"],
            timeout: 20.0
        )
        return try Self.parseList(output)
    }

    func outdated() async throws -> [PackageRecord] {
        guard let pip = pipPath else { return [] }
        // pip outdated is slow — it hits PyPI for every installed package.
        // 60s should cover all but extreme cases; if it times out the user
        // gets the badge-less list and an inline note.
        let output = try await Shell.run(
            pip,
            ["list", "--outdated", "--format=json", "--disable-pip-version-check"],
            timeout: 60.0
        )
        return try Self.parseOutdated(output)
    }

    func dependencies(of record: PackageRecord) async throws -> [String] { [] }
    func reverseDependencies(of record: PackageRecord) async throws -> [String] { [] }

    // MARK: - JSON parsing

    /// `pip list --format=json` shape:
    /// [{ "name": "<pkg>", "version": "1.2.3" }, ...]
    private static func parseList(_ jsonString: String) throws -> [PackageRecord] {
        guard let data = jsonString.data(using: .utf8) else { return [] }
        let rows = try JSONDecoder().decode([PipListRow].self, from: data)
        return rows.map { row in
            PackageRecord(
                id: "\(PipBackend.backendID)|pkg|\(row.name)",
                backendID: PipBackend.backendID,
                name: row.name,
                version: row.version,
                latestVersion: nil,
                summary: nil, homepage: nil, installedAt: nil,
                kind: .pip
            )
        }
    }

    /// `pip list --outdated --format=json` shape:
    /// [{ "name": "<pkg>", "version": "1.0", "latest_version": "1.1", ... }, ...]
    private static func parseOutdated(_ jsonString: String) throws -> [PackageRecord] {
        guard let data = jsonString.data(using: .utf8) else { return [] }
        let rows = try JSONDecoder().decode([PipOutdatedRow].self, from: data)
        return rows.map { row in
            PackageRecord(
                id: "\(PipBackend.backendID)|pkg|\(row.name)",
                backendID: PipBackend.backendID,
                name: row.name,
                version: row.version,
                latestVersion: row.latest_version,
                summary: nil, homepage: nil, installedAt: nil,
                kind: .pip
            )
        }
    }
}

// MARK: - Wire types

private struct PipListRow: Codable {
    let name: String
    let version: String?
}

private struct PipOutdatedRow: Codable {
    let name: String
    let version: String?
    let latest_version: String?
}
