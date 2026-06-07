// © Shimon Shmueli
import Foundation

/// One installed package or service shown in the Headless view.
/// Backend-agnostic so Homebrew formulae, npm globals, pip wheels, and
/// LaunchAgents can all coexist in the same UI list.
struct PackageRecord: Identifiable, Hashable {
    /// Unique across backends: `"<backendID>|<kind>|<name>"`.
    let id: String

    /// Which backend produced this row — used by the filter chip and the
    /// row's "Open homepage" / "Open Terminal with command" routing.
    let backendID: String

    /// Display name. For formulae and most CLIs this is the canonical id;
    /// for casks it's the human-readable name (`name[0]`).
    let name: String

    /// Currently installed version string. Nil for rows where the backend
    /// doesn't expose version info (rare).
    let version: String?

    /// Latest available version (filled in by the outdated() pass). Nil
    /// means "up to date" or "unknown" — the row treats both the same in v1.
    let latestVersion: String?

    /// One-line description. Nil if the backend doesn't expose one.
    let summary: String?

    /// Project homepage. Used by the "Open homepage" action.
    let homepage: URL?

    /// On-disk location of the install, when the backend can give us one
    /// (e.g. Cellar path for brew formulae). Used by "Show in Finder."
    let installedAt: URL?

    /// What kind of thing this is. Drives the row's secondary text and SF
    /// Symbol choice in the UI.
    let kind: Kind

    enum Kind: String, Codable, CaseIterable, Hashable {
        case formula        // brew formula
        case cask           // brew cask
        case npmGlobal      // npm install -g
        case pip            // pip install (user or system)
        case pipx           // pipx install
        case cargo          // cargo install
        case mise           // mise managed runtime
        case asdf           // asdf managed runtime
        case launchAgent    // user/global Launch Agent
        case launchDaemon   // global Launch Daemon
    }
}

/// One source of installed packages. Each concrete backend probes for the
/// underlying CLI at init time; if not present, `isAvailable` is false and
/// the rest of the methods short-circuit to empty results.
protocol PackageManager {
    /// Stable identifier used in cache keys and the filter UI (e.g. `"homebrew"`).
    static var backendID: String { get }

    /// Filter chip label (e.g. `"Homebrew"`).
    static var displayName: String { get }

    /// SF Symbol name for the chip / row icon (e.g. `"mug.fill"`).
    static var sfSymbol: String { get }

    /// True if the underlying CLI was found on this machine.
    var isAvailable: Bool { get }

    /// Enumerate every installed package. Heavy call — cache the result
    /// upstream rather than calling per row.
    func list() async throws -> [PackageRecord]

    /// Subset that has an upgrade available, with `latestVersion` filled in.
    /// Implemented in Step 3 of the plan.
    func outdated() async throws -> [PackageRecord]

    /// Forward dependencies of a record. Implemented in Step 5.
    func dependencies(of record: PackageRecord) async throws -> [String]

    /// Packages that depend on this one. Implemented in Step 5.
    func reverseDependencies(of record: PackageRecord) async throws -> [String]
}
