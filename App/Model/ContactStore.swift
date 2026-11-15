import AppKit
import Contacts
import ContacterCore
import Foundation

@MainActor
@Observable
final class ContactStore {
    enum Access: Equatable {
        case unknown, granted, denied
    }

    private(set) var access: Access = .unknown
    private(set) var cards: [ContactCard] = []
    private(set) var isLoading = false
    private(set) var duplicateGroups: [DuplicateGroup] = []
    private(set) var isScanning = false
    private(set) var lastBackup: URL?
    var errorMessage: String?

    // Auto-merge
    private(set) var history: [MergeRecord] = MergeHistoryFile.load()
    /// Automatic merges that happened since the history was last viewed.
    var unseenAutoMerges = 0
    /// Ids of duplicate groups the current policy would merge on its own.
    private(set) var autoMergeEligible: Set<String> = []
    private(set) var isAutoMerging = false
    var autoMergeEnabled: Bool = UserDefaults.standard.bool(forKey: "autoMergeEnabled") {
        didSet {
            UserDefaults.standard.set(autoMergeEnabled, forKey: "autoMergeEnabled")
            if autoMergeEnabled { Task { await runAutoMerge(automatic: true) } }
        }
    }
    var autoMergePolicy: AutoMergePolicy = ContactStore.loadPolicy() {
        didSet {
            if let data = try? JSONEncoder().encode(autoMergePolicy) {
                UserDefaults.standard.set(data, forKey: "autoMergePolicy")
            }
            refreshAutoMergeEligibility()
        }
    }
    /// Groups whose automatic merge failed this session (e.g. a read-only account); not retried until relaunch.
    @ObservationIgnored private var autoMergeFailures: Set<String> = []

    private var byID: [String: ContactCard] = [:]
    @ObservationIgnored private var searchIndex: [(id: String, text: String)] = []
    @ObservationIgnored private var thumbnails: [String: NSImage] = [:]
    @ObservationIgnored private(set) var duplicateIndex = DuplicateIndex([])
    @ObservationIgnored private var changeObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var reloadTask: Task<Void, Never>?

    private(set) var ignoredPairs: Set<ContactPair> {
        didSet { saveIgnoredPairs() }
    }

    let backupsDirectory: URL = URL.applicationSupportDirectory.appending(path: "Contacter/Backups", directoryHint: .isDirectory)

    init() {
        ignoredPairs = Self.loadIgnoredPairs()
        access = switch ContactsGateway.authorizationStatus() {
        case .authorized, .limited: .granted
        case .denied, .restricted: .denied
        default: .unknown
        }
        changeObserver = NotificationCenter.default.addObserver(forName: .CNContactStoreDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleReload() }
        }
        if access == .granted { scheduleReload() }
    }

    // MARK: - Loading

    func requestAccess() async {
        do {
            access = try await ContactsGateway.requestAccess() ? .granted : .denied
        } catch {
            access = .denied
        }
        if access == .granted { await reload() }
    }

    func reload() async {
        guard access == .granted else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let snapshot = try await ContactsGateway.fetchAll()
            let sorted = snapshot.cards.sorted {
                $0.sortKey.localizedStandardCompare($1.sortKey) == .orderedAscending
            }
            byID = Dictionary(sorted.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            searchIndex = sorted.map { ($0.id, $0.searchText) }
            thumbnails = snapshot.thumbnails.compactMapValues(NSImage.init(data:))
            duplicateIndex = DuplicateIndex(sorted)
            cards = sorted
            await scanForDuplicates()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Coalesces bursts of change notifications (ours and other apps') into one reload.
    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await reload()
        }
    }

    // MARK: - Lookup

    func card(id: String) -> ContactCard? { byID[id] }

    func thumbnail(id: String) -> NSImage? { thumbnails[id] }

    /// Every query word must appear somewhere in the contact (name, company, email, phone digits...).
    func search(_ query: String) -> [ContactCard] {
        let words = Normalize.tokens(query)
        guard !words.isEmpty else { return cards }
        return searchIndex.lazy
            .filter { entry in words.allSatisfy { entry.text.contains($0) } }
            .compactMap { self.byID[$0.id] }
    }

    func duplicateGroup(containing id: String) -> DuplicateGroup? {
        duplicateGroups.first { $0.memberIDs.contains(id) }
    }

    /// Existing contacts that look like a draft being typed in.
    func possibleDuplicates(of draft: ContactCard) -> [(card: ContactCard, match: PairMatch)] {
        guard !draft.isBlank else { return [] }
        return duplicateIndex.matches(for: draft, ignoring: ignoredPairs)
    }

    // MARK: - Editing

    @discardableResult
    func create(_ card: ContactCard) async -> String? {
        await perform { try await ContactsGateway.create(card) }
    }

    func update(_ card: ContactCard) async {
        await perform { try await ContactsGateway.update(card) }
    }

    func delete(ids: [String]) async {
        let directory = backupsDirectory
        if let backup = await perform({ try await ContactsGateway.delete(ids: ids, backupTo: directory) }) {
            lastBackup = backup
        }
    }

    // MARK: - Duplicates

    func scanForDuplicates() async {
        isScanning = true
        defer { isScanning = false }
        let snapshot = cards, ignored = ignoredPairs
        duplicateGroups = await Task.detached(priority: .userInitiated) {
            DuplicateFinder.findGroups(in: snapshot, ignoring: ignored)
        }.value
        refreshAutoMergeEligibility()
        if autoMergeEnabled && !isAutoMerging && !autoMergeEligible.isEmpty {
            await runAutoMerge(automatic: true)
        }
    }

    func mergePreview(_ group: DuplicateGroup, primaryID: String) -> ContactCard {
        ContactMerger.merge(group.memberIDs.compactMap(card(id:)), primaryID: primaryID)
    }

    func defaultPrimary(of group: DuplicateGroup) -> String {
        ContactMerger.defaultPrimary(of: group.memberIDs.compactMap(card(id:)))?.id ?? group.memberIDs[0]
    }

    /// Merges the group into `primaryID`. Returns the surviving contact id.
    @discardableResult
    func merge(_ group: DuplicateGroup, primaryID: String) async -> String? {
        await merge(ids: group.memberIDs, into: primaryID)
    }

    @discardableResult
    func merge(ids: [String], into primaryID: String) async -> String? {
        let reasons = duplicateGroups.first { Set($0.memberIDs) == Set(ids) }?.reasons ?? []
        do {
            try await performMerge(ids: ids, into: primaryID, reasons: reasons, automatic: false)
            await reload()
            return primaryID
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// The single path every merge goes through: back up, merge, record in history.
    private func performMerge(ids: [String], into primaryID: String, reasons: [String], automatic: Bool) async throws {
        let members = ids.compactMap(card(id:))
        guard members.count > 1 else { return }
        let merged = ContactMerger.merge(members, primaryID: primaryID)
        let others = members.map(\.id).filter { $0 != primaryID }
        let backup = try await ContactsGateway.merge(merged, removing: others, backupTo: backupsDirectory)
        lastBackup = backup
        let ordered = members.filter { $0.id == primaryID } + members.filter { $0.id != primaryID }
        history.insert(MergeRecord(date: .now, survivorID: primaryID, survivorName: merged.displayName,
                                   mergedNames: ordered.map(\.displayName), reasons: reasons,
                                   backupPath: backup.path(percentEncoded: false), automatic: automatic), at: 0)
        MergeHistoryFile.save(history)
        if automatic { unseenAutoMerges += 1 }
    }

    // MARK: - Auto-merge

    func autoMergeVerdict(for group: DuplicateGroup) -> AutoMergePolicy.Verdict {
        autoMergePolicy.verdict(for: group, cards: byID)
    }

    private func refreshAutoMergeEligibility() {
        autoMergeEligible = Set(duplicateGroups.filter { autoMergePolicy.isEligible($0, cards: byID) }.map(\.id))
    }

    /// Merges every group the policy accepts into its most complete contact, then reloads once.
    /// `automatic` runs (triggered by the setting) skip groups that already failed and report errors quietly.
    @discardableResult
    func runAutoMerge(automatic: Bool) async -> Int {
        guard !isAutoMerging, access == .granted else { return 0 }
        isAutoMerging = true
        defer { isAutoMerging = false }

        let groups = duplicateGroups.filter {
            autoMergeEligible.contains($0.id) && !(automatic && autoMergeFailures.contains($0.id))
        }
        guard !groups.isEmpty else { return 0 }
        var mergedCount = 0
        var failures: [String] = []
        for group in groups {
            // Re-check against current data: an earlier merge in this run may have changed things.
            guard autoMergePolicy.isEligible(group, cards: byID) else { continue }
            do {
                try await performMerge(ids: group.memberIDs, into: defaultPrimary(of: group),
                                       reasons: group.reasons, automatic: automatic)
                mergedCount += 1
            } catch {
                autoMergeFailures.insert(group.id)
                failures.append(error.localizedDescription)
            }
        }
        await reload()
        if !failures.isEmpty && !automatic {
            errorMessage = "\(failures.count) group(s) couldn't be merged: \(failures[0])"
        }
        return mergedCount
    }

    /// Restores the contacts a merge combined. They won't be suggested (or auto-merged) as duplicates again.
    func undo(_ record: MergeRecord) async {
        do {
            let restored = try await ContactsGateway.undoMerge(survivorID: record.survivorID, backup: record.backupURL)
            for a in restored {
                for b in restored where a < b { ignoredPairs.insert(ContactPair(a, b)) }
            }
            if let i = history.firstIndex(where: { $0.id == record.id }) {
                history[i].undoneAt = .now
                MergeHistoryFile.save(history)
            }
            await reload()
        } catch {
            errorMessage = "Couldn't undo the merge: \(error.localizedDescription)"
        }
    }

    /// Adds the fields of a typed draft to an existing contact instead of creating a duplicate.
    func addDraft(_ draft: ContactCard, to existingID: String) async {
        guard let existing = card(id: existingID) else { return }
        await update(ContactMerger.absorb(draft, into: existing))
    }

    func markNotDuplicates(_ group: DuplicateGroup) {
        for a in group.memberIDs {
            for b in group.memberIDs where a < b { ignoredPairs.insert(ContactPair(a, b)) }
        }
        duplicateGroups.removeAll { $0.id == group.id }
        refreshAutoMergeEligibility()
    }

    func resetIgnoredPairs() async {
        ignoredPairs = []
        await scanForDuplicates()
    }

    // MARK: - Helpers

    private func perform<T: Sendable>(_ work: @escaping @Sendable () async throws -> T) async -> T? {
        do {
            let result = try await work()
            await reload()
            return result
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private static func loadPolicy() -> AutoMergePolicy {
        guard let data = UserDefaults.standard.data(forKey: "autoMergePolicy"),
              let policy = try? JSONDecoder().decode(AutoMergePolicy.self, from: data) else { return AutoMergePolicy() }
        return policy
    }

    private static let ignoredKey = "ignoredDuplicatePairs"

    private static func loadIgnoredPairs() -> Set<ContactPair> {
        guard let data = UserDefaults.standard.data(forKey: ignoredKey),
              let pairs = try? JSONDecoder().decode(Set<ContactPair>.self, from: data) else { return [] }
        return pairs
    }

    private func saveIgnoredPairs() {
        if let data = try? JSONEncoder().encode(ignoredPairs) {
            UserDefaults.standard.set(data, forKey: Self.ignoredKey)
        }
    }
}

extension ContactCard {
    /// Sort by family name like Contacts does, falling back to whatever is displayed.
    var sortKey: String {
        familyName.isEmpty ? displayName : familyName + " " + givenName
    }
}
