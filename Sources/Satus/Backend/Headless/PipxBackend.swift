// © Shimon Shmueli
import Foundation

/// pipx-installed CLI tools (isolated venv per tool). The cleaner-signal
/// half of the Python world for a launcher: every entry is a tool the user
/// deliberately installed, not a transitive library.
///
/// pipx has no built-in `outdated` machinery, so v1 shows what's installed
/// without a latest-version comparison. Updates are still actionable via
/// `pipx upgrade <name>` in the context menu.
struct PipxBackend: PackageManager {

    static let backendID   = "pipx"
    static let displayName = "pipx"
    static let sfSymbol    = "tortoise.fill"

    private let pipxPath: String?

    init() {
        self.pipxPath = Shell.findBinary(candidates: [
            "/opt/homebrew/bin/pipx",
            "/usr/local/bin/pipx",
            // Fallback: pipx is sometimes installed user-local without brew.
            "\(NSHomeDirectory())/.local/bin/pipx"
        ])
    }

    var isAvailable: Bool { pipxPath != nil }

    func list() async throws -> [PackageRecord] {
        guard let pipx = pipxPath else { return [] }
        let output = try await Shell.run(pipx, ["list", "--json"], timeout: 15.0)
        return try Self.parse(output)
    }

    /// pipx has no outdated query; comparing installed vs PyPI's latest
    /// would need one HTTP call per package. Skipping in v1.
    func outdated() async throws -> [PackageRecord] { [] }

    func dependencies(of record: PackageRecord) async throws -> [String] { [] }
    func reverseDependencies(of record: PackageRecord) async throws -> [String] { [] }

    // MARK: - JSON parsing

    /// `pipx list --json` shape:
    /// {
    ///   "pipx_spec_version": "0.1",
    ///   "venvs": {
    ///     "<tool>": {
    ///       "metadata": { "main_package": { "package": "x", "package_version": "1.0" } }
    ///     },
    ///     ...
    ///   }
    /// }
    private static func parse(_ jsonString: String) throws -> [PackageRecord] {
        guard let data = jsonString.data(using: .utf8) else { return [] }
        let envelope = try JSONDecoder().decode(PipxEnvelope.self, from: data)
        return envelope.venvs?.map { name, venv in
            PackageRecord(
                id: "\(PipxBackend.backendID)|tool|\(name)",
                backendID: PipxBackend.backendID,
                name: name,
                version: venv.metadata?.main_package?.package_version,
                latestVersion: nil,
                summary: nil, homepage: nil, installedAt: nil,
                kind: .pipx
            )
        } ?? []
    }
}

// MARK: - Wire types

private struct PipxEnvelope: Codable {
    let venvs: [String: PipxVenv]?
}

private struct PipxVenv: Codable {
    let metadata: PipxMetadata?
}

private struct PipxMetadata: Codable {
    let main_package: PipxMainPackage?
}

private struct PipxMainPackage: Codable {
    let package: String?
    let package_version: String?
}
