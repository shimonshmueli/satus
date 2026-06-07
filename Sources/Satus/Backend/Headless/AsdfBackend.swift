// © Shimon Shmueli
import Foundation

/// asdf-managed runtimes. Older sibling of mise; many users still have it.
/// `asdf list` has no JSON option, so we hand-parse the two-level text:
///
///     nodejs
///       18.20.0
///       22.0.0
///     python
///       3.11.0
///       3.12.5
///
/// Each version becomes its own row labeled `<tool>@<version>`, matching
/// the MiseBackend's row shape so they sort and filter consistently.
struct AsdfBackend: PackageManager {

    static let backendID   = "asdf"
    static let displayName = "asdf"
    static let sfSymbol    = "arrow.triangle.branch"

    private let asdfPath: String?

    init() {
        // asdf is most often installed via brew or shell-init, with the
        // binary in one of these locations.
        self.asdfPath = Shell.findBinary(candidates: [
            "/opt/homebrew/bin/asdf",
            "/usr/local/bin/asdf",
            "\(NSHomeDirectory())/.asdf/bin/asdf"
        ])
    }

    var isAvailable: Bool { asdfPath != nil }

    func list() async throws -> [PackageRecord] {
        guard let asdf = asdfPath else { return [] }
        let output = try await Shell.run(asdf, ["list"], timeout: 15.0)
        return Self.parseList(output)
    }

    func outdated() async throws -> [PackageRecord] { [] }
    func dependencies(of record: PackageRecord) async throws -> [String] { [] }
    func reverseDependencies(of record: PackageRecord) async throws -> [String] { [] }

    // MARK: - Text parser

    static func parseList(_ raw: String) -> [PackageRecord] {
        var currentTool: String? = nil
        var records: [PackageRecord] = []
        for rawLine in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine)
            if line.first?.isWhitespace == true {
                // Indented = version under the current tool.
                guard let tool = currentTool else { continue }
                // asdf prefixes the active version with " *"; strip that and
                // any other leading whitespace/markers.
                let cleaned = line
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "*"))
                    .trimmingCharacters(in: .whitespaces)
                guard !cleaned.isEmpty else { continue }
                records.append(PackageRecord(
                    id: "\(AsdfBackend.backendID)|\(tool)@\(cleaned)",
                    backendID: AsdfBackend.backendID,
                    name: "\(tool)@\(cleaned)",
                    version: cleaned,
                    latestVersion: nil,
                    summary: nil, homepage: nil, installedAt: nil,
                    kind: .asdf
                ))
            } else {
                // Unindented = tool header.
                let cleaned = line.trimmingCharacters(in: .whitespaces)
                guard !cleaned.isEmpty else { continue }
                currentTool = cleaned
            }
        }
        return records
    }
}
