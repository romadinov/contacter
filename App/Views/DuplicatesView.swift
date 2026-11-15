import ContacterCore
import SwiftUI

struct DuplicateListView: View {
    @Environment(ContactStore.self) private var store
    @Binding var selection: String?

    @State private var minimum: MatchConfidence = .low
    @State private var confirmMergeAll = false

    var body: some View {
        let groups = store.duplicateGroups.filter { $0.confidence >= minimum }
        let autoCount = store.autoMergeEligible.count

        List(groups, selection: $selection) { group in
            DuplicateGroupRow(
                names: group.memberIDs.compactMap { store.card(id: $0)?.displayName },
                firstID: group.memberIDs[0],
                initials: store.card(id: group.memberIDs[0])?.initials ?? "?",
                confidence: group.confidence,
                reasons: group.reasons,
                autoMergeable: store.autoMergeEligible.contains(group.id)
            )
            .tag(group.id)
        }
        .safeAreaInset(edge: .top) {
            Picker("Show", selection: $minimum) {
                Text("All").tag(MatchConfidence.low)
                Text("Medium+").tag(MatchConfidence.medium)
                Text("High").tag(MatchConfidence.high)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .overlay {
            if store.isScanning && store.duplicateGroups.isEmpty {
                ProgressView("Scanning…")
            } else if groups.isEmpty {
                ContentUnavailableView("No Duplicates", systemImage: "checkmark.circle",
                                       description: Text("Your contacts look clean."))
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button("Rescan", systemImage: "arrow.clockwise") { Task { await store.scanForDuplicates() } }
                    .disabled(store.isScanning)
                Button("Auto-Merge", systemImage: "bolt.badge.checkmark") { confirmMergeAll = true }
                    .disabled(autoCount == 0 || store.isAutoMerging)
                    .help("Merge the \(autoCount) group(s) that meet the auto-merge rules (Settings › Auto-Merge)")
            }
        }
        .confirmationDialog("Auto-merge \(autoCount) group(s)?", isPresented: $confirmMergeAll) {
            Button("Merge \(autoCount) Groups", role: .destructive) {
                Task {
                    selection = nil
                    await store.runAutoMerge(automatic: false)
                }
            }
        } message: {
            Text("Groups marked with ⚡ meet the auto-merge rules. Each is merged into its most complete contact. Every merge is backed up and can be undone from Merge History.")
        }
    }
}

private struct DuplicateGroupRow: View {
    let names: [String]
    let firstID: String
    let initials: String
    let confidence: MatchConfidence
    let reasons: [String]
    let autoMergeable: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarView(id: firstID, initials: initials, size: 30)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(names.first ?? "").lineLimit(1)
                    if names.count > 1 {
                        Text("×\(names.count)").foregroundStyle(.secondary)
                    }
                    Spacer()
                    if autoMergeable {
                        Image(systemName: "bolt.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                            .help("Meets the auto-merge rules")
                    }
                    ConfidenceBadge(confidence: confidence)
                }
                Text(reasons.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Side-by-side comparison of a duplicate group, a choice of which contact to keep, and a preview of the merge.
struct DuplicateGroupView: View {
    @Environment(ContactStore.self) private var store
    let group: DuplicateGroup

    @State private var primaryID: String?
    @State private var confirmMerge = false
    @State private var isMerging = false

    var body: some View {
        let members = group.memberIDs.compactMap(store.card(id:))
        let primary = primaryID ?? store.defaultPrimary(of: group)
        let preview = store.mergePreview(group, primaryID: primary)

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("\(members.count) contacts look like the same person").font(.title3.weight(.semibold))
                            ConfidenceBadge(confidence: group.confidence)
                        }
                        Text(group.reasons.joined(separator: " · ")).foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                AutoMergeVerdictLabel(verdict: store.autoMergeVerdict(for: group),
                                      names: Dictionary(members.map { ($0.id, $0.displayName) }, uniquingKeysWith: { a, _ in a }))

                Text("Choose the contact to keep. Everything else is copied into it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(members) { card in
                            MemberCard(card: card, isPrimary: card.id == primary) { primaryID = card.id }
                        }
                    }
                    .padding(2)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("After merging", systemImage: "arrow.triangle.merge").font(.headline)
                    HStack(alignment: .top, spacing: 12) {
                        AvatarView(id: primary, initials: preview.initials, size: 44)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(preview.displayName).font(.title3.weight(.medium))
                            CardFieldsView(card: preview)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.green.opacity(0.08), in: .rect(cornerRadius: 10))
                }

                HStack {
                    Button("Not Duplicates") { store.markNotDuplicates(group) }
                    Spacer()
                    Button("Merge \(members.count) Contacts") { confirmMerge = true }
                        .buttonStyle(.borderedProminent)
                        .disabled(isMerging || members.count < 2)
                }
            }
            .padding(20)
        }
        .confirmationDialog("Merge into \(preview.displayName)?", isPresented: $confirmMerge) {
            Button("Merge", role: .destructive) {
                Task {
                    isMerging = true
                    await store.merge(group, primaryID: primary)
                    isMerging = false
                }
            }
        } message: {
            Text("\(members.count - 1) contact(s) will be deleted after their details are copied. A vCard backup is saved first.")
        }
    }
}

private struct MemberCard: View {
    let card: ContactCard
    let isPrimary: Bool
    let choose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                AvatarView(id: card.id, initials: card.initials, size: 36)
                VStack(alignment: .leading) {
                    Text(card.displayName).font(.headline).lineLimit(1)
                    if !card.organization.isEmpty, !card.isCompany {
                        Text(card.organization).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            CardFieldsView(card: card)
            Spacer(minLength: 0)
            Button(action: choose) {
                Label(isPrimary ? "Keeping this one" : "Keep this one",
                      systemImage: isPrimary ? "checkmark.circle.fill" : "circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(isPrimary ? Color.accentColor : .secondary)
        }
        .padding(12)
        .frame(width: 260, alignment: .leading)
        .frame(minHeight: 160)
        .background(.background.secondary, in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isPrimary ? Color.accentColor : .clear, lineWidth: 2)
        }
        .contentShape(.rect)
        .onTapGesture(perform: choose)
    }
}

/// Explains whether the group would be auto-merged, and if not, which rule stops it.
private struct AutoMergeVerdictLabel: View {
    let verdict: AutoMergePolicy.Verdict
    let names: [String: String]

    private func name(_ id: String) -> String { names[id] ?? "?" }

    var body: some View {
        Label(text, systemImage: verdict == .eligible ? "bolt.fill" : "bolt.slash")
            .font(.callout)
            .foregroundStyle(verdict == .eligible ? AnyShapeStyle(.yellow) : AnyShapeStyle(.secondary))
    }

    private var text: String {
        switch verdict {
        case .eligible: "Meets the auto-merge rules"
        case .tooLarge: "Not auto-merged: group is larger than the auto-merge limit"
        case .weakPair(let a, let b): "Not auto-merged: \(name(a)) and \(name(b)) don't match strongly enough"
        case .noSharedIdentifier(let a, let b):
            "Not auto-merged: \(name(a)) and \(name(b)) share no email, phone or social profile"
        case .nameConflict(let a, let b): "Not auto-merged: \(name(a)) and \(name(b)) have different names"
        case .missingContact: "Not auto-merged: a contact in this group no longer exists"
        }
    }
}
