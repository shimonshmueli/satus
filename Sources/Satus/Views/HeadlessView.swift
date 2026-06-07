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

    enum SortMode: String, CaseIterable, Identifiable {
        case name = "Name"
        case backend = "Backend"
        case versionOutdatedFirst = "Outdated first"
        var id: String { rawValue }
    }

    // Available backends. Step 6–9 add npm / pip / cargo / mise here.
    private var availableBackends: [(id: String, name: String, symbol: String)] {
        var out: [(id: String, name: String, symbol: String)] = []
        if HomebrewBackend().isAvailable {
            out.append((id: HomebrewBackend.backendID,
                        name: HomebrewBackend.displayName,
                        symbol: HomebrewBackend.sfSymbol))
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
    }

    // MARK: - Header (filter chips + search + sort + refresh)

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                chip(label: "All", symbol: "circle.grid.2x2",
                     isActive: activeBackendID == "all") { activeBackendID = "all" }
                ForEach(availableBackends, id: \.id) { be in
                    chip(label: be.name, symbol: be.symbol,
                         isActive: activeBackendID == be.id) { activeBackendID = be.id }
                }
                Spacer()
                Button {
                    Task { await loadAll() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh")
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
                      isActive: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.caption)
                Text(label).font(.caption)
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
                        RecordRow(record: record)
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

    private func loadAll() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        var collected: [PackageRecord] = []
        do {
            let brew = HomebrewBackend()
            if brew.isAvailable {
                collected.append(contentsOf: try await brew.list())
            }
            records = collected
        } catch {
            loadError = error.localizedDescription
        }
    }
}

// MARK: - Row

private struct RecordRow: View {
    let record: PackageRecord

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
