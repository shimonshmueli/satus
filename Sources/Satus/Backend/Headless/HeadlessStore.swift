// © Shimon Shmueli
import Foundation
import SwiftUI

/// Holds the Headless view's data outside the view's lifetime, so switching
/// the sidebar to a different selection and back doesn't reset state or
/// re-trigger a load. SwiftUI destroys and recreates `HeadlessView` on
/// every sidebar switch; without a persistent store the user sees an
/// apparent "refresh" each time they re-enter Headless.
///
/// Singleton because there's only ever one Headless view in the app.
@MainActor
final class HeadlessStore: ObservableObject {

    static let shared = HeadlessStore()

    @Published var records: [PackageRecord] = []
    @Published var isLoading: Bool = false
    @Published var loadError: String? = nil
    @Published var actionStatus: String? = nil

    /// Set true after the first successful first-pass load. `loadIfNeeded()`
    /// short-circuits subsequent calls so re-entering Headless is instant.
    private var hasLoadedOnce: Bool = false

    private init() {}

    /// Called by `HeadlessView.task`. First call kicks off a real load;
    /// subsequent calls (sidebar swap → re-entry) do nothing.
    func loadIfNeeded() async {
        guard !hasLoadedOnce else { return }
        await loadAll(forceRefresh: false)
        hasLoadedOnce = true
    }

    /// The full progressive-load path. Cache hits paint instantly; cache
    /// misses show the fast `list()` first and then enrich with `outdated()`
    /// in the background per backend.
    func loadAll(forceRefresh: Bool = false) async {
        isLoading = true
        loadError = nil

        let backends: [any PackageManager] = [
            HomebrewBackend(), NpmBackend(), PipxBackend(), PipBackend(),
            CargoBackend(), MiseBackend(), AsdfBackend(), LaunchServicesBackend()
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

        // Fast list() per backend that needs fetching, then a background
        // outdated() enrichment per backend independent of the others.
        do {
            var listed: [String: [PackageRecord]] = [:]
            for backend in needsFetch {
                let id = type(of: backend).backendID
                let fast = try await backend.list()
                listed[id] = fast
                records.append(contentsOf: fast)
            }
            isLoading = false

            for backend in needsFetch {
                let id = type(of: backend).backendID
                let fast = listed[id] ?? []
                Task {
                    do {
                        let outdated = try await backend.outdated()
                        let merged = Self.merge(list: fast, outdated: outdated)
                        await MainActor.run {
                            records.removeAll { $0.backendID == id }
                            records.append(contentsOf: merged)
                        }
                        HeadlessCache.save(backendID: id, records: merged)
                    } catch {
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
}
