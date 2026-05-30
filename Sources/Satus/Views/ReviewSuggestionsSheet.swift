// © Shimon Shmueli
#if SATUS_PRO
import SwiftUI
import AppKit

/// Stage-2 review sheet: per-app accept/reject for LLM-suggested assignments
/// drawn from the user's existing tags. Additive only — never removes tags.
struct ReviewSuggestionsSheet: View {
    @EnvironmentObject var appService: AppService
    @Environment(\.dismiss) private var dismiss

    let assignments: [ValidatedAssignment]

    struct Row: Identifiable {
        var id: String { assignment.bundleID }
        let assignment: ValidatedAssignment
        var accepted: Bool
    }

    @State private var rows: [Row] = []

    // MARK: - View

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    Text("App Assignments (\(rows.count))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    ForEach($rows) { $row in
                        AppAssignmentRow(
                            row: $row,
                            allTags: appService.tags,
                            appsByID: appsByID
                        )
                        Divider().opacity(0.3)
                    }
                }
                .padding()
            }
            Divider()
            footer
        }
        .frame(minWidth: 640, idealWidth: 720, minHeight: 520, idealHeight: 640)
        .onAppear { buildInitialState() }
    }

    private var header: some View {
        HStack {
            Text("Review Suggestions")
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
            .help("Cancel without applying")
        }
        .padding()
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Select ≥ 0.8") {
                for i in rows.indices {
                    rows[i].accepted = rows[i].assignment.confidence >= 0.8
                                       && !rows[i].assignment.existingTagIDs.isEmpty
                }
            }
            .help("Accept only rows the model was at least 80% confident about")
            Button("Reject all") {
                for i in rows.indices { rows[i].accepted = false }
            }
            Spacer()
            Button("Cancel") { dismiss() }
            Button("Apply \(applicableCount)") {
                applyChanges()
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(applicableCount == 0)
        }
        .padding()
    }

    // MARK: - Derived

    private var appsByID: [String: AppItem] {
        Dictionary(uniqueKeysWithValues: appService.apps.map { ($0.id, $0) })
    }

    /// An accepted row only counts toward Apply if it actually carries at least
    /// one existing tag suggestion — empty assignments add nothing.
    private var applicableCount: Int {
        rows.reduce(0) { count, row in
            count + (row.accepted && !row.assignment.existingTagIDs.isEmpty ? 1 : 0)
        }
    }

    // MARK: - State init

    private func buildInitialState() {
        rows = assignments
            .filter { !$0.existingTagIDs.isEmpty }
            .sorted { $0.confidence > $1.confidence }
            .map { Row(assignment: $0, accepted: true) }
    }

    // MARK: - Apply

    private func applyChanges() {
        let tagsByID = Dictionary(uniqueKeysWithValues: appService.tags.map { ($0.id, $0) })
        for row in rows where row.accepted {
            for tagID in row.assignment.existingTagIDs {
                if let tag = tagsByID[tagID] {
                    appService.assignTag(tag, to: row.assignment.bundleID)
                }
            }
        }
    }
}

// MARK: - Row

private struct AppAssignmentRow: View {
    @Binding var row: ReviewSuggestionsSheet.Row
    let allTags: [AppTag]
    let appsByID: [String: AppItem]

    var body: some View {
        let app = appsByID[row.assignment.bundleID]
        let tagNames: [String] = row.assignment.existingTagIDs.compactMap { id in
            allTags.first { $0.id == id }?.name
        }

        HStack(alignment: .center, spacing: 12) {
            Toggle("", isOn: $row.accepted)
                .labelsHidden()

            Group {
                if let app = app {
                    Image(nsImage: app.icon).resizable()
                } else {
                    Image(systemName: "app.dashed").resizable().foregroundColor(.secondary)
                }
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(app?.name ?? row.assignment.bundleID)
                    .font(.subheadline)
                HStack(spacing: 4) {
                    ForEach(tagNames, id: \.self) { name in
                        Text(name)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.secondary.opacity(0.22)))
                    }
                }
            }
            .help(row.assignment.rationale.isEmpty
                  ? "(No rationale provided)"
                  : row.assignment.rationale)

            Spacer()

            Text(String(format: "%.0f%%", row.assignment.confidence * 100))
                .font(.caption2.monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
        .padding(.vertical, 2)
        .opacity(row.accepted ? 1.0 : 0.55)
    }
}
#endif
