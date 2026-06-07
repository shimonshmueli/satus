// © Shimon Shmueli
import Foundation

/// Globally installed cargo binaries (`cargo install <crate>`).
///
/// cargo deliberately does not ship a JSON output for `install --list`,
/// so we hand-parse the text. Format:
///
///     package-name v1.2.3:
///         binary-1
///         binary-2
///     other-pkg v0.4.0 (https://github.com/foo/bar):
///         other-pkg
///
/// We only care about the top-level `package-name vX.Y.Z` lines — the
/// indented binary lines are noise for our row model.
///
/// cargo has no built-in outdated check; `cargo-outdated` would have to be
/// installed separately. v1 skips outdated for cargo.
struct CargoBackend: PackageManager {

    static let backendID   = "cargo"
    static let displayName = "cargo"
    static let sfSymbol    = "shippingbox"

    private let cargoPath: String?

    init() {
        self.cargoPath = Shell.findBinary(candidates: [
            // rustup's standard install location — preferred over brew's
            // cargo because it tracks the user's active toolchain.
            "\(NSHomeDirectory())/.cargo/bin/cargo",
            "/opt/homebrew/bin/cargo",
            "/usr/local/bin/cargo"
        ])
    }

    var isAvailable: Bool { cargoPath != nil }

    func list() async throws -> [PackageRecord] {
        guard let cargo = cargoPath else { return [] }
        let output = try await Shell.run(cargo, ["install", "--list"], timeout: 15.0)
        return Self.parseInstallList(output)
    }

    func outdated() async throws -> [PackageRecord] { [] }
    func dependencies(of record: PackageRecord) async throws -> [String] { [] }
    func reverseDependencies(of record: PackageRecord) async throws -> [String] { [] }

    // MARK: - Hand-rolled parser

    /// Walks `cargo install --list` text. A "package" line is unindented and
    /// matches the shape `name vVERSION[ (some-source)]:`. Indented lines
    /// list the bin targets and are ignored here.
    static func parseInstallList(_ raw: String) -> [PackageRecord] {
        var records: [PackageRecord] = []
        for rawLine in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine)
            // Indented lines list binary targets under the previous package;
            // we only care about the top-level package lines.
            if line.first?.isWhitespace == true { continue }
            // Strip trailing colon (always present on the package line).
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasSuffix(":") else { continue }
            let body = String(trimmed.dropLast())  // remove trailing ':'
            // Split off optional " (source)" suffix.
            let beforeParen = body.split(separator: " (", maxSplits: 1).first.map(String.init) ?? body
            // "name vVERSION" — split on the last space; the trailing
            // version must start with 'v'.
            let parts = beforeParen.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2 else { continue }
            let versionToken = String(parts.last!)
            guard versionToken.hasPrefix("v") else { continue }
            let name = parts.dropLast().joined(separator: " ")
            let version = String(versionToken.dropFirst())
            records.append(PackageRecord(
                id: "\(CargoBackend.backendID)|crate|\(name)",
                backendID: CargoBackend.backendID,
                name: name,
                version: version,
                latestVersion: nil,
                summary: nil, homepage: nil, installedAt: nil,
                kind: .cargo
            ))
        }
        return records
    }
}
