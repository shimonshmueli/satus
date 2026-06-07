// © Shimon Shmueli
import SwiftUI
import AppKit

/// Step-2 shell of the Headless view.
/// - Filter chips (one per available backend; Homebrew only for now)
/// - Inline search field
/// - Sort menu
/// - Scrollable list of `PackageRecord`s
///
/// Rows are inert in Step 2 (click → noop). Actions (Show in Finder,
/// Copy update command, Open Terminal pre-typed) come in Step 4.
struct HeadlessView: View {

    @State private var records: [PackageRecord] = []
    @State private var isLoading: Bool = false
    @State private var loadError: String? = nil

    @State private var searchText: String = ""
    @State private var activeBackendID: String = "all"   // "all" or a specific backendID
    @State private var sortMode: SortMode = .name

    // Step 5: when the user picks "View dependencies" on a row, we set this
    // to the record and a sheet binding to it opens. PackageRecord is
    // Identifiable so `.sheet(item:)` is the right modifier.
    @State private var inspectingRecord: PackageRecord? = nil

    enum SortMode: String, CaseIterable, Identifiable {
        case name = "Name"
        case backend = "Backend"
        case versionOutdatedFirst = "Outdated first"
        var id: String { rawValue }
    }

    // Available backends. Steps 7–10 add pip / cargo / mise / LaunchAgents.
    private var availableBackends: [(id: String, name: String, symbol: String)] {
        var out: [(id: String, name: String, symbol: String)] = []
        if HomebrewBackend().isAvailable {
            out.append((id: HomebrewBackend.backendID,
                        name: HomebrewBackend.displayName,
                        symbol: HomebrewBackend.sfSymbol))
        }
        if NpmBackend().isAvailable {
            out.append((id: NpmBackend.backendID,
                        name: NpmBackend.displayName,
                        symbol: NpmBackend.sfSymbol))
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.top, 4)
            content
        }
        .padding(.horizontal)
        .task { await loadAll() }
        .sheet(item: $inspectingRecord) { record in
            DependencySheet(record: record)
        }
    }

    // MARK: - Header (filter chips + search + sort + refresh)

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                let totalOutdated = records.lazy.filter { $0.latestVersion != nil }.count
                chip(label: "All", symbol: "circle.grid.2x2",
                     badge: totalOutdated > 0 ? "\(totalOutdated)" : nil,
                     isActive: activeBackendID == "all") { activeBackendID = "all" }
                ForEach(availableBackends, id: \.id) { be in
                    let count = outdatedCount(for: be.id)
                    chip(label: be.name, symbol: be.symbol,
                         badge: count > 0 ? "\(count)" : nil,
                         isActive: activeBackendID == be.id) { activeBackendID = be.id }
                }
                Spacer()
                Button {
                    // Explicit user-driven refresh — bypass the disk cache
                    // and re-run `brew list` + `brew outdated` now.
                    Task { await loadAll(forceRefresh: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh (bypass cache)")
                .disabled(isLoading)
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Filter by name", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                Picker("", selection: $sortMode) {
                    ForEach(SortMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 150)
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func chip(label: String,
                      symbol: String,
                      badge: String? = nil,
                      isActive: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.caption)
                Text(label).font(.caption)
                if let badge = badge {
                    // Outdated-count pill on the chip — orange to draw the eye
                    // without screaming red.
                    Text(badge)
                        .font(.caption2.monospacedDigit().bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.orange))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(isActive ? Color.accentColor.opacity(0.25)
                                                : Color.secondary.opacity(0.12)))
            .overlay(Capsule().strokeBorder(isActive ? Color.accentColor
                                                    : Color.secondary.opacity(0.3),
                                            lineWidth: 1))
            .foregroundColor(isActive ? Color.accentColor : .primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content (loading state / error / list)

    @ViewBuilder
    private var content: some View {
        if isLoading && records.isEmpty {
            HStack {
                Spacer()
                ProgressView("Scanning installed packages…")
                    .controlSize(.small)
                Spacer()
            }
            .padding(.top, 40)
        } else if let err = loadError {
            VStack(alignment: .leading, spacing: 6) {
                Text("Failed to load: \(err)")
                    .font(.caption)
                    .foregroundColor(.red)
                Button("Retry") { Task { await loadAll() } }
                    .buttonStyle(.bordered)
            }
            .padding(.top, 20)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let visible = filteredAndSorted(records)
                    HStack {
                        Text("\(visible.count) packages")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    ForEach(visible) { record in
                        RecordRow(record: record, onInspect: { inspectingRecord = $0 })
                        Divider().opacity(0.2)
                    }
                }
                .padding(.bottom, 12)
            }
        }
    }

    // MARK: - Filter + sort

    private func filteredAndSorted(_ all: [PackageRecord]) -> [PackageRecord] {
        var out = all
        if activeBackendID != "all" {
            out = out.filter { $0.backendID == activeBackendID }
        }
        if !searchText.isEmpty {
            let needle = searchText.lowercased()
            out = out.filter { $0.name.lowercased().contains(needle) }
        }
        switch sortMode {
        case .name:
            out.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .backend:
            out.sort {
                if $0.backendID == $1.backendID {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return $0.backendID < $1.backendID
            }
        case .versionOutdatedFirst:
            // Step 3 fills latestVersion; for now this is just name order.
            out.sort {
                let lhsOutdated = $0.latestVersion != nil
                let rhsOutdated = $1.latestVersion != nil
                if lhsOutdated != rhsOutdated { return lhsOutdated }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
        return out
    }

    // MARK: - Loading

    /// Progressive load across all available backends.
    /// Per backend, three paths:
    ///   1. Cache hit (within TTL): show cached records, done.
    ///   2. Cache miss, fast list first: show `list()` records immediately
    ///      (sub-second), then fire `outdated()` in the background and
    ///      merge its badges into the visible list when it returns.
    ///   3. Force refresh: invalidate cache, run the same fast-then-slow flow.
    private func loadAll(forceRefresh: Bool = false) async {
        isLoading = true
        loadError = nil

        let backends: [any PackageManager] = [
            HomebrewBackend(), NpmBackend()
        ].filter { $0.isAvailable }

        guard !backends.isEmpty else {
            isLoading = false
            return
        }

        // Start with whatever's cached so the first paint is instant for
        // backends that have a fresh entry.
        var firstPass: [PackageRecord] = []
        var needsFetch: [any PackageManager] = []
        for backend in backends {
            let id = type(of: backend).backendID
            if forceRefresh {
                HeadlessCache.invalidate(backendID: id)
            }
            if let cached = HeadlessCache.load(backendID: id) {
                firstPass.append(contentsOf: cached.records)
            } else {
                needsFetch.append(backend)
            }
        }
        records = firstPass

        guard !needsFetch.isEmpty else {
            isLoading = false
            return
        }

        // For backends that need fetching: fast list first, then enrich.
        do {
            var listed: [String: [PackageRecord]] = [:]   // backendID -> records
            for backend in needsFetch {
                let id = type(of: backend).backendID
                let fast = try await backend.list()
                listed[id] = fast
                records.append(contentsOf: fast)
            }
            isLoading = false   // spinner clears as soon as the fast lists are in

            // Run outdated() per backend in the background, independently.
            // A slow brew doesn't block npm and vice versa.
            for backend in needsFetch {
                let id = type(of: backend).backendID
                let fast = listed[id] ?? []
                Task {
                    do {
                        let outdated = try await backend.outdated()
                        let merged = Self.merge(list: fast, outdated: outdated)
                        await MainActor.run {
                            // Replace just this backend's slice of the records.
                            records.removeAll { $0.backendID == id }
                            records.append(contentsOf: merged)
                        }
                        HeadlessCache.save(backendID: id, records: merged)
                    } catch {
                        // Cache the fast list so next launch isn't slow,
                        // and surface a non-fatal note for the user.
                        HeadlessCache.save(backendID: id, records: fast)
                        await MainActor.run {
                            loadError = "\(id) outdated check failed: \(error.localizedDescription)"
                        }
                    }
                }
            }
        } catch {
            isLoading = false
            loadError = error.localizedDescription
        }
    }

    /// Merges `outdated` (carries `latestVersion`) onto `list` by `id`.
    /// Anything in `list` that doesn't appear outdated keeps `latestVersion == nil`.
    private static func merge(list: [PackageRecord],
                              outdated: [PackageRecord]) -> [PackageRecord] {
        let outdatedByID = Dictionary(uniqueKeysWithValues: outdated.map { ($0.id, $0) })
        return list.map { row in
            guard let o = outdatedByID[row.id] else { return row }
            return PackageRecord(
                id: row.id,
                backendID: row.backendID,
                name: row.name,
                version: row.version ?? o.version,
                latestVersion: o.latestVersion,
                summary: row.summary,
                homepage: row.homepage,
                installedAt: row.installedAt,
                kind: row.kind
            )
        }
    }

    /// Count of outdated records for a given backend (used by the chip badge).
    fileprivate func outdatedCount(for backendID: String) -> Int {
        records.lazy
            .filter { $0.backendID == backendID && $0.latestVersion != nil }
            .count
    }
}

// MARK: - Row

private struct RecordRow: View {
    let record: PackageRecord
    /// Step 5: parent opens the DependencySheet when the menu item fires.
    let onInspect: (PackageRecord) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: symbolForKind(record.kind))
                .frame(width: 22, height: 22)
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(record.name).font(.subheadline.weight(.medium))
                    if let v = record.version {
                        Text(v)
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    if let latest = record.latestVersion {
                        // The orange chip means: there's a newer version
                        // available. Action to upgrade comes in Step 4.
                        Text("→ \(latest)")
                            .font(.caption2.monospacedDigit().bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.orange))
                    }
                }
                if let summary = record.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(record.kind.rawValue)
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.secondary.opacity(0.12)))
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .contextMenu {
            // All actions in Step 4 are read-only ZoneKey-side. We don't
            // run brew ourselves — either copy the command, open the
            // homepage, reveal the install path in Finder, or hand the
            // command off to Terminal. Direct execution lives in v2 (Pro).
            if let homepage = homepageURL(for: record) {
                Button("Open homepage") {
                    NSWorkspace.shared.open(homepage)
                }
            }
            if let installURL = installPathURL(for: record) {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([installURL])
                }
            }
            // Dependencies popover only applies to brew formulae; casks have
            // no meaningful dep info and we shouldn't waste a shell call on them.
            if record.backendID == HomebrewBackend.backendID && record.kind == .formula {
                Button("View dependencies…") {
                    onInspect(record)
                }
            }
            Divider()
            if let upgradeCmd = upgradeCommand(for: record) {
                Button("Copy update command") {
                    copyToClipboard(upgradeCmd)
                }
                Button("Open Terminal and run update") {
                    runInTerminal(upgradeCmd)
                }
            }
            if let uninstallCmd = uninstallCommand(for: record) {
                Divider()
                Button("Copy uninstall command") {
                    copyToClipboard(uninstallCmd)
                }
            }
        }
    }

    // MARK: - Context menu helpers

    /// URL of the package's catalog page. We use formulae.brew.sh for brew
    /// records since it's a reliable, always-present landing page that
    /// links to the upstream project homepage. Avoids an extra `brew info`
    /// call just to expose this action in the menu.
    private func homepageURL(for record: PackageRecord) -> URL? {
        switch record.backendID {
        case HomebrewBackend.backendID:
            let kindSegment = record.kind == .cask ? "cask" : "formula"
            return URL(string: "https://formulae.brew.sh/\(kindSegment)/\(record.name)")
        case NpmBackend.backendID:
            return URL(string: "https://www.npmjs.com/package/\(record.name)")
        default:
            return record.homepage
        }
    }

    /// On-disk path of the install (Cellar / Caskroom). Falls back to the
    /// Homebrew root if the deeper directory doesn't exist.
    private func installPathURL(for record: PackageRecord) -> URL? {
        switch record.backendID {
        case HomebrewBackend.backendID:
            let candidates: [String] = {
                let dir = record.kind == .cask ? "Caskroom" : "Cellar"
                return [
                    "/opt/homebrew/\(dir)/\(record.name)",
                    "/usr/local/\(dir)/\(record.name)"
                ]
            }()
            for path in candidates where FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
            return nil
        default:
            return record.installedAt
        }
    }

    private func upgradeCommand(for record: PackageRecord) -> String? {
        switch record.backendID {
        case HomebrewBackend.backendID:
            return record.kind == .cask
                ? "brew upgrade --cask \(record.name)"
                : "brew upgrade \(record.name)"
        case NpmBackend.backendID:
            return "npm update -g \(record.name)"
        default:
            return nil   // Steps 7–9 add pip / cargo / mise
        }
    }

    private func uninstallCommand(for record: PackageRecord) -> String? {
        switch record.backendID {
        case HomebrewBackend.backendID:
            return record.kind == .cask
                ? "brew uninstall --cask \(record.name)"
                : "brew uninstall \(record.name)"
        case NpmBackend.backendID:
            return "npm uninstall -g \(record.name)"
        default:
            return nil
        }
    }

    private func copyToClipboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    /// Hands the command to Terminal.app via AppleScript. `do script` opens
    /// a new Terminal window and runs the command. We don't try to "type
    /// without enter" — that path needs Accessibility permission and is
    /// jankier than just executing in a fresh window the user can see.
    private func runInTerminal(_ command: String) {
        // Escape backslashes and double-quotes for the AppleScript string
        // literal; backslash first so the second pass doesn't double-escape.
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Terminal"
            activate
            do script "\(escaped)"
        end tell
        """
        if let appleScript = NSAppleScript(source: script) {
            var err: NSDictionary?
            appleScript.executeAndReturnError(&err)
            // If err is non-nil it usually means user denied Automation
            // permission for Terminal. Silently fail — the macOS prompt
            // already told them what to do.
        }
    }

    private func symbolForKind(_ kind: PackageRecord.Kind) -> String {
        switch kind {
        case .formula, .cask:       return "mug.fill"
        case .npmGlobal:            return "shippingbox.fill"
        case .pip, .pipx:           return "tortoise.fill"
        case .cargo:                return "shippingbox"
        case .mise, .asdf:          return "arrow.triangle.branch"
        case .launchAgent:          return "gear.badge"
        case .launchDaemon:         return "gear.badge.checkmark"
        }
    }
}
