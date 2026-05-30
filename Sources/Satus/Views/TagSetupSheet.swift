// © Shimon Shmueli
#if SATUS_PRO
import SwiftUI
import AppKit

/// Stage-1 sheet: let the user rename, recolor, delete, or add tags before
/// the LLM classifies anything. Nothing mutates AppService until "Continue".
/// On Cancel, no diff is applied — the existing tag set stays as-is.
struct TagSetupSheet: View {
    @EnvironmentObject var appService: AppService
    @Environment(\.dismiss) private var dismiss

    /// Called after the diff is applied to AppService. The caller kicks off
    /// classification with the now-current tag set.
    var onContinue: () -> Void

    /// One editable row. `originalID == nil` means the row was added in this
    /// sheet and doesn't yet exist on AppService.
    struct Row: Identifiable {
        let id: UUID = UUID()
        var originalID: UUID?
        var name: String
        var colorHex: String
        var isDeleted: Bool = false
    }

    @State private var rows: [Row] = []

    // Default color for newly added rows — picked from the seed palette to
    // stay visually consistent with the seven defaults.
    private static let defaultNewColor = "#8E8E93"

    // MARK: - View

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tags (\(activeCount))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    ForEach($rows) { $row in
                        if !row.isDeleted {
                            tagRow($row)
                        }
                    }
                    Button {
                        rows.append(Row(originalID: nil, name: "New Tag", colorHex: Self.defaultNewColor))
                    } label: {
                        Label("Add tag", systemImage: "plus.circle")
                    }
                    .buttonStyle(.borderless)
                    .padding(.top, 4)
                }
                .padding()
            }
            Divider()
            footer
        }
        .frame(minWidth: 520, idealWidth: 600, minHeight: 420, idealHeight: 520)
        .onAppear { buildInitialState() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Set Up Tags")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Cancel without changes")
            }
            Text("Rename, recolor, delete, or add tags before the LLM classifies your apps. Descriptions are only sent to the model for tags that still match a default seed name.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }

    @ViewBuilder
    private func tagRow(_ row: Binding<Row>) -> some View {
        HStack(spacing: 10) {
            ColorPicker("", selection: Binding(
                get: { Color.fromHex(row.wrappedValue.colorHex) },
                set: { row.wrappedValue.colorHex = $0.toHex() }
            ))
            .labelsHidden()
            .frame(width: 32, height: 24)

            TextField("Tag name", text: row.name)
                .textFieldStyle(.roundedBorder)

            if let desc = DefaultTags.description(forName: row.wrappedValue.name) {
                Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
                    .help(desc)
            }

            Button {
                row.wrappedValue.isDeleted = true
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Delete this tag")
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Reset to defaults") { resetToDefaults() }
                .help("Replace the current list with the seven seed tags")
            Spacer()
            Button("Cancel") { dismiss() }
            Button("Continue") {
                applyDiffToAppService()
                dismiss()
                onContinue()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(activeCount == 0)
        }
        .padding()
    }

    private var activeCount: Int {
        rows.filter { !$0.isDeleted && !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }.count
    }

    // MARK: - State init

    private func buildInitialState() {
        rows = appService.tags.map {
            Row(originalID: $0.id, name: $0.name, colorHex: $0.colorHex ?? Self.defaultNewColor)
        }
        // If the user has somehow cleared all tags, prime with the seeds.
        if rows.isEmpty {
            rows = DefaultTags.all.map {
                Row(originalID: nil, name: $0.name, colorHex: $0.colorHex)
            }
        }
    }

    private func resetToDefaults() {
        // Mark every existing row as deleted, then add fresh seed rows.
        for i in rows.indices where rows[i].originalID != nil {
            rows[i].isDeleted = true
        }
        rows.removeAll { $0.originalID == nil }
        for seed in DefaultTags.all {
            rows.append(Row(originalID: nil, name: seed.name, colorHex: seed.colorHex))
        }
    }

    // MARK: - Apply (diff against AppService)

    private func applyDiffToAppService() {
        // 1) Deletions first, so renames don't trip on stale UUIDs.
        for row in rows where row.isDeleted {
            if let id = row.originalID {
                appService.deleteTag(id: id)
            }
        }
        // 2) Updates (rename + recolor) for surviving original rows.
        for row in rows where !row.isDeleted {
            guard let id = row.originalID else { continue }
            if let current = appService.tags.first(where: { $0.id == id }) {
                let trimmed = row.name.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty && trimmed != current.name {
                    appService.renameTag(id: id, newName: trimmed)
                }
                if row.colorHex != (current.colorHex ?? "") {
                    appService.setTagColor(id: id, colorHex: row.colorHex)
                }
            }
        }
        // 3) Additions.
        for row in rows where !row.isDeleted && row.originalID == nil {
            let trimmed = row.name.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if let created = appService.addTag(name: trimmed) {
                appService.setTagColor(id: created.id, colorHex: row.colorHex)
            }
        }
    }
}
#endif
