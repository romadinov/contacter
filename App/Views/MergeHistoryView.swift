import SwiftUI

struct MergeHistoryView: View {
    @Environment(ContactStore.self) private var store
    @Binding var selection: UUID?

    var body: some View {
        List(store.history, selection: $selection) { record in
            MergeRecordRow(name: record.survivorName, count: record.mergedNames.count, date: record.date,
                           automatic: record.automatic, undone: record.undoneAt != nil)
                .tag(record.id)
        }
        .overlay {
            if store.history.isEmpty {
                ContentUnavailableView("No Merges Yet", systemImage: "clock.arrow.circlepath",
                                       description: Text("Merges you make, by hand or automatically, appear here and can be undone."))
            }
        }
        .onAppear { store.unseenAutoMerges = 0 }
    }
}

private struct MergeRecordRow: View {
    let name: String
    let count: Int
    let date: Date
    let automatic: Bool
    let undone: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: automatic ? "bolt.fill" : "arrow.triangle.merge")
                .foregroundStyle(automatic ? .yellow : .secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).strikethrough(undone).lineLimit(1)
                Text("\(count) contacts · \(date.formatted(.relative(presentation: .named)))\(undone ? " · undone" : "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct MergeRecordDetail: View {
    @Environment(ContactStore.self) private var store
    let record: MergeRecord

    @State private var confirmUndo = false
    @State private var isUndoing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label(record.automatic ? "Merged automatically" : "Merged by you",
                      systemImage: record.automatic ? "bolt.fill" : "arrow.triangle.merge")
                    .foregroundStyle(.secondary)
                Text(record.survivorName).font(.title2.weight(.semibold))
                Text(record.date.formatted(date: .long, time: .shortened)).foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Combined").font(.headline)
                    ForEach(Array(record.mergedNames.enumerated()), id: \.offset) { index, name in
                        Label(name, systemImage: index == 0 ? "checkmark.circle.fill" : "minus.circle")
                            .foregroundStyle(index == 0 ? .primary : .secondary)
                    }
                }
                if !record.reasons.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Why").font(.headline)
                        Text(record.reasons.joined(separator: " · ")).foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Button("Show Backup in Finder") { NSWorkspace.shared.activateFileViewerSelecting([record.backupURL]) }
                        .disabled(!FileManager.default.fileExists(atPath: record.backupPath))
                    Spacer()
                    if let undoneAt = record.undoneAt {
                        Text("Undone \(undoneAt.formatted(.relative(presentation: .named)))").foregroundStyle(.secondary)
                    } else {
                        Button("Undo Merge") { confirmUndo = true }
                            .disabled(isUndoing || !FileManager.default.fileExists(atPath: record.backupPath))
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .confirmationDialog("Undo this merge?", isPresented: $confirmUndo) {
            Button("Undo Merge", role: .destructive) {
                Task {
                    isUndoing = true
                    await store.undo(record)
                    isUndoing = false
                }
            }
        } message: {
            Text("\(record.survivorName) is replaced by the \(record.mergedNames.count) original contacts from the backup. Edits made to it since the merge are lost. The restored contacts won't be suggested as duplicates again.")
        }
    }
}
