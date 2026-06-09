// © Shimon Shmueli
import Foundation

/// Globally-installed npm packages. Uses npm's machine-readable JSON output
/// for both list and outdated, so parsing is symmetric with the brew path.
///
/// Note on probing: we accept the standard Homebrew-installed npm at
/// `/opt/homebrew/bin/npm` (and `/usr/local/bin/npm` on Intel). Users with
/// nvm/asdf/Volta-managed Node aren't probed in v1; if there's demand we
/// can also try the active `~/.local/share/...` shims later. Step 9 of the
/// plan covers the mise/asdf runtime case more thoroughly.
struct NpmBackend: PackageManager {

    static let backendID   = "npm"
    static let displayName = "npm"
    static let sfSymbol    = "shippingbox.fill"

    private let npmPath: String?

    init() {
        self.npmPath = Shell.findBinary(candidates: [
            "/opt/homebrew/bin/npm",   // brew-installed npm on Apple Silicon
            "/usr/local/bin/npm"        // brew-installed npm on Intel
        ])
    }

    var isAvailable: Bool { npmPath != nil }

    func list() async throws -> [PackageRecord] {
        guard let npm = npmPath else { return [] }
        // `--depth=0` keeps the result to direct globals; `--json` gives a
        // stable shape. npm sometimes warns on stderr (peer-dep complaints)
        // but exits 0 — we don't treat stderr as fatal.
        let output = try await Shell.run(npm,
                                         ["ls", "-g", "--depth=0", "--json"],
                                         timeout: 15.0)
        return try Self.parseList(output)
    }

    func outdated() async throws -> [PackageRecord] {
        guard let npm = npmPath else { return [] }
        // `npm outdated` exits with code 1 when anything is outdated — that
        // is its normal "result" signal, not an error. Shell.run() throws
        // on non-zero exit, so we catch and treat exit==1 with valid JSON
        // on stdout as success. If parsing also fails, propagate the
        // original throw so the user sees a real error message.
        do {
            let output = try await Shell.run(npm,
                                             ["outdated", "-g", "--json"],
                                             timeout: 15.0)
            return try Self.parseOutdated(output)
        } catch let Shell.Failure.nonZeroExit(_, _, body) {
            // body is stderr; the actual outdated JSON went to stdout but
            // we can't see it after the throw. Re-run with a pipe-aware
            // path: ignore stderr, accept exit=1, parse stdout.
            return try await fallbackOutdated(npm: npmPath!) ?? []
        }
    }

    func dependencies(of record: PackageRecord) async throws -> [String] {
        // Global npm packages don't typically have user-meaningful direct
        // deps for our purposes; the popover would just list internal
        // transitive deps which adds noise. Empty in v1.
        return []
    }

    func reverseDependencies(of record: PackageRecord) async throws -> [String] {
        // Same reasoning — global installs don't depend on each other.
        return []
    }

    // MARK: - Outdated fallback (npm exits 1 when anything is outdated)

    /// Runs `npm outdated -g --json` accepting exit==1 as a normal result.
    /// Used when Shell.run() throws nonZeroExit for the "everything is
    /// outdated" case. Returns nil if even this path fails.
    private func fallbackOutdated(npm: String) async throws -> [PackageRecord]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: npm)
        process.arguments = ["outdated", "-g", "--json"]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (env["PATH"] ?? "") + ":/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        process.environment = env

        try process.run()
        process.waitUntilExit()
        // Accept 0 or 1; everything else is a real failure.
        guard process.terminationStatus == 0 || process.terminationStatus == 1 else {
            return nil
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? "{}"
        return try Self.parseOutdated(text)
    }

    // MARK: - JSON parsing

    /// `npm ls -g --depth=0 --json` returns:
    /// {
    ///   "name": "lib", "version": "...",
    ///   "dependencies": {
    ///     "<pkg>": { "version": "1.2.3", ... },
    ///     ...
    ///   }
    /// }
    private static func parseList(_ jsonString: String) throws -> [PackageRecord] {
        guard let data = jsonString.data(using: .utf8) else { return [] }
        let envelope = try JSONDecoder().decode(NpmListEnvelope.self, from: data)
        return envelope.dependencies?.map { name, info in
            PackageRecord(
                id: "\(NpmBackend.backendID)|global|\(name)",
                backendID: NpmBackend.backendID,
                name: name,
                version: info.version,
                latestVersion: nil,
                summary: nil, homepage: nil, installedAt: nil,
                kind: .npmGlobal
            )
        } ?? []
    }

    /// `npm outdated -g --json` returns:
    /// {
    ///   "<pkg>": { "current": "1.0.0", "wanted": "1.0.1", "latest": "1.2.0", ... },
    ///   ...
    /// }
    /// Empty object means nothing outdated.
    private static func parseOutdated(_ jsonString: String) throws -> [PackageRecord] {
        guard let data = jsonString.data(using: .utf8) else { return [] }
        let dict = try JSONDecoder().decode([String: NpmOutdatedInfo].self, from: data)
        return dict.map { name, info in
            PackageRecord(
                id: "\(NpmBackend.backendID)|global|\(name)",
                backendID: NpmBackend.backendID,
                name: name,
                version: info.current,
                latestVersion: info.latest ?? info.wanted,
                summary: nil, homepage: nil, installedAt: nil,
                kind: .npmGlobal
            )
        }
    }
}

// MARK: - Wire types

private struct NpmListEnvelope: Codable {
    let dependencies: [String: NpmListInfo]?
}

private struct NpmListInfo: Codable {
    let version: String?
}

private struct NpmOutdatedInfo: Codable {
    let current: String?
    let wanted: String?
    let latest: String?
}
