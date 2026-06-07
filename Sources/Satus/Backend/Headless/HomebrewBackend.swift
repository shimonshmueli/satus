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

    // Stubs filled in by Steps 3 and 5 of the plan.
    func outdated() async throws -> [PackageRecord] { [] }
    func dependencies(of record: PackageRecord) async throws -> [String] { [] }
    func reverseDependencies(of record: PackageRecord) async throws -> [String] { [] }

    // MARK: - Output parsing

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
