// © Shimon Shmueli
import Foundation

/// LaunchAgents and LaunchDaemons — the macOS background-service plists.
/// Scans the three standard directories, parses each `.plist`, surfaces
/// rows. No CLI to probe; isAvailable is always true.
///
/// In v1 we don't cross-reference `launchctl list` for load state. The
/// listing itself answers the "what is this thing on my Mac" question
/// for a non-CLI-savvy user; enable/disable belongs in v2 (Pro execution
/// layer) where it can wrap `launchctl bootstrap`/`bootout` with the
/// right scope and confirmation.
struct LaunchServicesBackend: PackageManager {

    static let backendID   = "launch"
    static let displayName = "Launch"
    static let sfSymbol    = "gear.badge"

    /// User Agents → user's own .plist files. Global Agents and Daemons
    /// → installed system-wide; readable but writable only as root.
    enum Scope: String {
        case userAgent     = "User Agent"
        case globalAgent   = "Global Agent"
        case globalDaemon  = "Global Daemon"

        var directory: URL {
            switch self {
            case .userAgent:
                return URL(fileURLWithPath: "\(NSHomeDirectory())/Library/LaunchAgents",
                           isDirectory: true)
            case .globalAgent:
                return URL(fileURLWithPath: "/Library/LaunchAgents", isDirectory: true)
            case .globalDaemon:
                return URL(fileURLWithPath: "/Library/LaunchDaemons", isDirectory: true)
            }
        }

        var kind: PackageRecord.Kind {
            self == .globalDaemon ? .launchDaemon : .launchAgent
        }
    }

    var isAvailable: Bool { true }

    func list() async throws -> [PackageRecord] {
        // Scanning the three directories is cheap (a few dozen plists at most
        // on a typical machine) but we still hand it to a background thread
        // so the UI isn't blocked if a plist read stalls on slow disk.
        return await Task.detached(priority: .userInitiated) {
            var rows: [PackageRecord] = []
            for scope in [Scope.userAgent, .globalAgent, .globalDaemon] {
                rows.append(contentsOf: LaunchServicesBackend.scan(scope: scope))
            }
            return rows
        }.value
    }

    func outdated() async throws -> [PackageRecord] { [] }
    func dependencies(of record: PackageRecord) async throws -> [String] { [] }
    func reverseDependencies(of record: PackageRecord) async throws -> [String] { [] }

    // MARK: - Scan

    /// Walks a directory, returning a `PackageRecord` per readable `.plist`.
    /// Malformed plists are silently skipped — we don't want one bad file
    /// to break the whole list.
    private static func scan(scope: Scope) -> [PackageRecord] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: scope.directory,
                                                        includingPropertiesForKeys: nil,
                                                        options: [.skipsHiddenFiles])
        else { return [] }

        var rows: [PackageRecord] = []
        for url in entries where url.pathExtension.lowercased() == "plist" {
            guard let row = readPlist(at: url, scope: scope) else { continue }
            rows.append(row)
        }
        return rows
    }

    /// Reads one plist, extracts the Label and program path. Falls back to
    /// the filename (minus `.plist`) if no Label key is present, which is
    /// uncommon but legal.
    private static func readPlist(at url: URL, scope: Scope) -> PackageRecord? {
        guard let data = try? Data(contentsOf: url),
              let raw = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil),
              let dict = raw as? [String: Any]
        else { return nil }

        let labelFallback = url.deletingPathExtension().lastPathComponent
        let label = dict["Label"] as? String ?? labelFallback

        // Program lookup order: Program (single path), then
        // ProgramArguments[0] (argv-style).
        let program: String? = {
            if let p = dict["Program"] as? String { return p }
            if let args = dict["ProgramArguments"] as? [String],
               let first = args.first { return first }
            return nil
        }()

        return PackageRecord(
            id: "\(LaunchServicesBackend.backendID)|\(scope.rawValue)|\(label)",
            backendID: LaunchServicesBackend.backendID,
            name: label,
            version: scope.rawValue,       // "User Agent" / "Global Agent" / "Global Daemon"
            latestVersion: nil,
            summary: program,              // the executable path
            homepage: nil,
            installedAt: url,              // the .plist itself
            kind: scope.kind
        )
    }
}
