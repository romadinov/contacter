import Foundation

/// One merge (manual or automatic), with what's needed to undo it.
struct MergeRecord: Codable, Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var survivorID: String
    var survivorName: String
    /// Display names of every contact that went into the merge, survivor first.
    var mergedNames: [String]
    var reasons: [String]
    var backupPath: String
    var automatic: Bool
    var undoneAt: Date?

    var backupURL: URL { URL(filePath: backupPath) }
}

/// Persists merge records as JSON next to the backups.
enum MergeHistoryFile {
    static let url = URL.applicationSupportDirectory.appending(path: "Contacter/merge-history.json")

    static func load() -> [MergeRecord] {
        guard let data = try? Data(contentsOf: url),
              let records = try? JSONDecoder().decode([MergeRecord].self, from: data) else { return [] }
        return records
    }

    static func save(_ records: [MergeRecord]) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(records).write(to: url, options: .atomic)
        } catch {
            assertionFailure("Couldn't save merge history: \(error)")
        }
    }
}
