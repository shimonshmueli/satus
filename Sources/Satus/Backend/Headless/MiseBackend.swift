// © Shimon Shmueli
import Foundation

/// mise (formerly rtx) managed runtimes — Node, Python, Ruby, Go, Java,
/// etc. installed in version-managed slots. Each installed version shows
/// as its own row labeled `<tool>@<version>` so the user can see what's
/// on disk and which is active.
///
/// `mise ls --json` outputs an array of rows. v1 shows installed versions
/// without "is there a newer one" comparison — mise has `mise outdated`
/// but its semantics are coupled to project pinning and not useful for a
/// machine-wide overview.
struct MiseBackend: PackageManager {

    static let backendID   = "mise"
    static let displayName = "mise"
    static let sfSymbol    = "arrow.triangle.branch"

    private let misePath: String?

    init() {
        self.misePath = Shell.findBinary(candidates: [
            "/opt/homebrew/bin/mise",
            "/usr/local/bin/mise",
            "\(NSHomeDirectory())/.local/bin/mise"
        ])
    }

    var isAvailable: Bool { misePath != nil }

    func list() async throws -> [PackageRecord] {
        guard let mise = misePath else { return [] }
        let output = try await Shell.run(mise, ["ls", "--json"], timeout: 15.0)
        return try Self.parse(output)
    }

    func outdated() async throws -> [PackageRecord] { [] }
    func dependencies(of record: PackageRecord) async throws -> [String] { [] }
    func reverseDependencies(of record: PackageRecord) async throws -> [String] { [] }

    // MARK: - JSON parsing

    /// `mise ls --json` output: an array of installed-version entries.
    /// Each carries at minimum a `name` (the tool, e.g. "node") and a
    /// `version` (e.g. "22.0.0"). Extra fields like `active`, `requested_version`,
    /// and `install_path` are ignored in v1.
    private static func parse(_ jsonString: String) throws -> [PackageRecord] {
        guard let data = jsonString.data(using: .utf8) else { return [] }
        let rows = try JSONDecoder().decode([MiseRow].self, from: data)
        return rows.compactMap { row in
            guard let name = row.name, let version = row.version else { return nil }
            return PackageRecord(
                id: "\(MiseBackend.backendID)|\(name)@\(version)",
                backendID: MiseBackend.backendID,
                name: "\(name)@\(version)",
                version: version,
                latestVersion: nil,
                summary: row.install_path,
                homepage: nil,
                installedAt: row.install_path.flatMap { URL(fileURLWithPath: $0) },
                kind: .mise
            )
        }
    }
}

// MARK: - Wire types

private struct MiseRow: Codable {
    let name: String?
    let version: String?
    let install_path: String?
}
