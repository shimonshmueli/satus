// © Shimon Shmueli
import Foundation

/// Homebrew formulae + casks. Uses `brew info --json=v2 --installed` which
/// returns the rich envelope in a single call (name, version, description,
/// homepage) — cheaper than calling `brew list` + `brew info <pkg>` per row.
struct HomebrewBackend: PackageManager {

    static let backendID   = "homebrew"
    static let displayName = "Homebrew"
    static let sfSymbol    = "mug.fill"

    private let brewPath: String?

    init() {
        // Probe at known install locations. We don't rely on $PATH because
        // ZoneKey's launch environment may not include the user's shell paths.
        self.brewPath = Shell.findBinary(candidates: [
            "/opt/homebrew/bin/brew",   // Apple Silicon Homebrew
            "/usr/local/bin/brew"       // Intel Homebrew (still common)
        ])
    }

    var isAvailable: Bool { brewPath != nil }

    func list() async throws -> [PackageRecord] {
        guard let brew = brewPath else { return [] }
        // Generous timeout — power-user machines with many formulae take
        // several seconds for this call. Step 3 will add caching.
        let output = try await Shell.run(brew,
                                         ["info", "--json=v2", "--installed"],
                                         timeout: 30.0)
        return try Self.parse(output)
    }

    // Stubs filled in by Steps 3 and 5 of the plan.
    func outdated() async throws -> [PackageRecord] { [] }
    func dependencies(of record: PackageRecord) async throws -> [String] { [] }
    func reverseDependencies(of record: PackageRecord) async throws -> [String] { [] }

    // MARK: - JSON parsing

    private static func parse(_ jsonString: String) throws -> [PackageRecord] {
        guard let data = jsonString.data(using: .utf8) else { return [] }
        let envelope = try JSONDecoder().decode(BrewEnvelope.self, from: data)

        let formulaeRecords = envelope.formulae.map { $0.toRecord() }
        let caskRecords     = envelope.casks.map { $0.toRecord() }
        return formulaeRecords + caskRecords
    }
}

// MARK: - Wire types (brew info --json=v2 --installed)

/// Top-level envelope. Both arrays are always present; either can be empty.
private struct BrewEnvelope: Codable {
    let formulae: [BrewFormula]
    let casks: [BrewCask]
}

private struct BrewFormula: Codable {
    let name: String
    let desc: String?
    let homepage: String?
    let installed: [InstalledVersion]

    struct InstalledVersion: Codable {
        let version: String
    }

    func toRecord() -> PackageRecord {
        PackageRecord(
            id: "\(HomebrewBackend.backendID)|formula|\(name)",
            backendID: HomebrewBackend.backendID,
            name: name,
            version: installed.first?.version,
            latestVersion: nil,
            summary: desc,
            homepage: homepage.flatMap { URL(string: $0) },
            installedAt: nil,
            kind: .formula
        )
    }
}

private struct BrewCask: Codable {
    let token: String
    let name: [String]?
    let desc: String?
    let homepage: String?
    let installed: String?      // casks expose this as a single version string

    func toRecord() -> PackageRecord {
        // `name` is an array of display names; the first entry is the
        // canonical user-facing label (e.g. "Visual Studio Code" for `vscode`).
        let displayName = name?.first ?? token
        return PackageRecord(
            id: "\(HomebrewBackend.backendID)|cask|\(token)",
            backendID: HomebrewBackend.backendID,
            name: displayName,
            version: installed,
            latestVersion: nil,
            summary: desc,
            homepage: homepage.flatMap { URL(string: $0) },
            installedAt: nil,
            kind: .cask
        )
    }
}
