// © Shimon Shmueli
import SwiftUI

/// Two-column view of a package's forward ("Depends on") and reverse
/// ("Used by") dependencies. Lazy-fetches both lists in parallel on appear.
/// Step-5 scope: directly installed deps only — no transitive tree.
struct DependencySheet: View {
    @Environment(\.dismiss) private var dismiss

    let record: PackageRecord

    @State private var forward: [String] = []
    @State private var reverse: [String] = []
    @State private var isLoading: Bool = true
    @State private var loadError: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if isLoading {
                loadingState
            } else if let err = loadError {
                errorState(err)
            } else {
                content
            }
            Divider()
            footer
        }
        .frame(minWidth: 520, idealWidth: 600, minHeight: 360, idealHeight: 460)
        .task { await load() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Dependencies").font(.headline)
                Text(record.name)
                    .font(.subheadline.monospaced())
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }

    private var loadingState: some View {
        HStack {
            Spacer()
            ProgressView("Resolving…").controlSize(.small)
            Spacer()
        }
        .padding(.vertical, 40)
    }

    private func errorState(_ err: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Failed to resolve dependencies")
                .font(.subheadline.bold())
                .foregroundColor(.red)
            Text(err).font(.caption).foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var content: some View {
        HStack(alignment: .top, spacing: 12) {
            column(title: "Depends on", subtitle: "What \(record.name) needs",
                   items: forward, emptyHint: "No dependencies.")
            Divider()
            column(title: "Used by", subtitle: "Installed packages that need \(record.name)",
                   items: reverse, emptyHint: "Nothing currently installed depends on this.")
        }
        .padding()
    }

    private func column(title: String,
                        subtitle: String,
                        items: [String],
                        emptyHint: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title).font(.subheadline.bold())
                if !items.isEmpty {
                    Text("\(items.count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.secondary.opacity(0.12)))
                }
            }
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
            if items.isEmpty {
                Text(emptyHint)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
                    .padding(.top, 8)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(items, id: \.self) { name in
                            Text(name)
                                .font(.subheadline.monospaced())
                                .padding(.vertical, 1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Close") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding()
    }

    // MARK: - Load

    private func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let brew = HomebrewBackend()
            async let fwd = brew.dependencies(of: record)
            async let rev = brew.reverseDependencies(of: record)
            let (f, r) = try await (fwd, rev)
            forward = f
            reverse = r
        } catch {
            loadError = error.localizedDescription
        }
    }
}
