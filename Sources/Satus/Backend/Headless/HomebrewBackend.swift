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

        // Use the FAST path: `brew list --versions --<kind>` returns one line
        // per package as `name v1 v2 ...`. Sub-second even on a 200-package
        // brew. We accept the trade-off of no descriptions/homepages here;
        // those come from on-demand `brew info --json=v2 <name>` in Step 5
        // (dependency popover) or via background enrichment in Step 3.
        async let formulaeOut = Shell.run(brew, ["list", "--versions", "--formula"], timeout: 15.0)
        async let casksOut    = Shell.run(brew, ["list", "--versions", "--cask"],    timeout: 15.0)
        let (formulae, casks) = try await (formulaeOut, casksOut)

        let formulaRecords = parseListVersions(formulae, kind: .formula)
        let caskRecords    = parseListVersions(casks,    kind: .cask)
        return formulaRecords + caskRecords
    }

    /// Returns one record per outdated package, with `latestVersion` populated.
    /// Caller merges this against the result of `list()` to set indicators.
    func outdated() async throws -> [PackageRecord] {
        guard let brew = brewPath else { return [] }
        // `brew outdated --json=v2` is fast (no Cellar walk; consults cached
        // formula metadata). 8s is generous on a 200-formula brew.
        // Slow on machines with many formulae — brew walks homebrew-core
        // to compute latest versions. Observed: ~25s on a 162-package brew.
        let output = try await Shell.run(brew,
                                         ["outdated", "--json=v2"],
                                         timeout: 60.0)
        return try Self.parseOutdated(output)
    }

    func dependencies(of record: PackageRecord) async throws -> [String] {
        guard let brew = brewPath else { return [] }
        // Cask dependency info isn't meaningful — casks bundle their deps
        // inside the app. Skip the call.
        guard record.kind == .formula else { return [] }
        let output = try await Shell.run(brew, ["deps", record.name], timeout: 15.0)
        return Self.parseLines(output)
    }

    func reverseDependencies(of record: PackageRecord) async throws -> [String] {
        guard let brew = brewPath else { return [] }
        guard record.kind == .formula else { return [] }
        // `--installed` restricts the result to formulae the user actually
        // has — the unrestricted form returns the entire homebrew-core graph.
        let output = try await Shell.run(brew,
                                         ["uses", "--installed", record.name],
                                         timeout: 15.0)
        return Self.parseLines(output)
    }

    /// Splits a newline-separated CLI output into trimmed non-empty lines.
    private static func parseLines(_ raw: String) -> [String] {
        raw.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Output parsing

    /// Decodes the `brew outdated --json=v2` envelope into records.
    /// Each record carries `latestVersion`; `version` is the currently
    /// installed one. Other fields are left nil since merge-by-name into
    /// the full list will fill them in.
    private static func parseOutdated(_ jsonString: String) throws -> [PackageRecord] {
        guard let data = jsonString.data(using: .utf8) else { return [] }
        let envelope = try JSONDecoder().decode(BrewOutdatedEnvelope.self, from: data)

        let formulaRecords: [PackageRecord] = envelope.formulae.map { f in
            PackageRecord(
                id: "\(HomebrewBackend.backendID)|formula|\(f.name)",
                backendID: HomebrewBackend.backendID,
                name: f.name,
                version: f.installed_versions.first,
                latestVersion: f.current_version,
                summary: nil, homepage: nil, installedAt: nil,
                kind: .formula
            )
        }
        let caskRecords: [PackageRecord] = envelope.casks.map { c in
            PackageRecord(
                id: "\(HomebrewBackend.backendID)|cask|\(c.name)",
                backendID: HomebrewBackend.backendID,
                name: c.name,
                // Cask installed_versions can be string OR array depending on
                // brew version; we accept both via FlexibleInstalledVersions.
                version: c.installed_versions.first,
                latestVersion: c.current_version,
                summary: nil, homepage: nil, installedAt: nil,
                kind: .cask
            )
        }
        return formulaRecords + caskRecords
    }

    /// `brew list --versions` output is one line per package, space-separated:
    ///     git 2.50.0_1
    ///     python@3.12 3.12.5 3.12.6
    /// We keep the first (highest-priority) installed version per row.
    private func parseListVersions(_ raw: String,
                                   kind: PackageRecord.Kind) -> [PackageRecord] {
        var out: [PackageRecord] = []
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard let nameToken = parts.first else { continue }
            let name = String(nameToken)
            let version = parts.dropFirst().first.map(String.init)
            let idKind = kind == .formula ? "formula" : "cask"
            out.append(PackageRecord(
                id: "\(HomebrewBackend.backendID)|\(idKind)|\(name)",
                backendID: HomebrewBackend.backendID,
                name: name,
                version: version,
                latestVersion: nil,
                summary: nil,       // filled in by lazy enrichment, see plan
                homepage: nil,      // same
                installedAt: nil,
                kind: kind
            ))
        }
        return out
    }
}

// MARK: - Wire types (brew outdated --json=v2)

private struct BrewOutdatedEnvelope: Codable {
    let formulae: [Formula]
    let casks: [Cask]

    struct Formula: Codable {
        let name: String
        let installed_versions: [String]
        let current_version: String
    }

    /// Casks: brew alternates between a string and an array for
    /// `installed_versions` across versions. Accept either.
    struct Cask: Codable {
        let name: String
        let installed_versions: FlexibleInstalledVersions
        let current_version: String
    }

    /// Decodes either a single string or an array of strings into [String].
    struct FlexibleInstalledVersions: Codable {
        let first: String?

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let single = try? c.decode(String.self) {
                self.first = single
            } else if let arr = try? c.decode([String].self) {
                self.first = arr.first
            } else {
                self.first = nil
            }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            try c.encode(first ?? "")
        }
    }
}
