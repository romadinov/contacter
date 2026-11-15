import ContacterCore
import SwiftUI

/// The Cardhop-style input: one field that searches, creates ("Jane Doe jane@acme.com 555-1234"),
/// and acts ("call Jane"). Creating checks for existing look-alikes first.
struct QuickEntryView: View {
    @Environment(ContactStore.self) private var store
    @Binding var selection: String?
    var compact = false

    @State private var query = ""
    @State private var pendingDraft: ContactCard?
    @FocusState private var fieldFocused: Bool

    var body: some View {
        let entry = QuickEntryParser.parse(query)
        let results = results(for: entry)
        let draft = draftToOffer(entry, results: results)
        let duplicates = draft.map { store.possibleDuplicates(of: $0.card) } ?? []

        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: icon(for: entry)).foregroundStyle(.secondary)
                TextField("Search, or type a new contact…", text: $query)
                    .textFieldStyle(.plain)
                    .font(compact ? .title3 : .body)
                    .focused($fieldFocused)
                    .onSubmit { submit(entry, results: results, draft: draft?.card, duplicates: duplicates) }
                    .onKeyPress(.downArrow) { moveSelection(by: 1, in: results) }
                    .onKeyPress(.upArrow) { moveSelection(by: -1, in: results) }
                    .onKeyPress(.escape) {
                        guard !query.isEmpty else { return .ignored }
                        query = ""
                        return .handled
                    }
                if !query.isEmpty {
                    Button("Clear", systemImage: "xmark.circle.fill") { query = "" }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)

            if let hint = hint(for: entry, results: results, draft: draft?.card, duplicates: duplicates) {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }
            Divider()

            if let draft {
                DraftPreview(draft: draft.card, leftovers: draft.leftovers, duplicates: duplicates,
                             onCreate: { Task { await create(draft.card) } },
                             onAddTo: { id in Task { await add(draft.card, to: id) } })
                Divider()
            }

            List(results, selection: $selection) { card in
                ContactRow(card: card).tag(card.id)
            }
            .overlay {
                if results.isEmpty && draft == nil && !store.isLoading {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
        .onAppear { fieldFocused = true }
        .confirmationDialog("This looks like a contact you already have",
                            isPresented: Binding(get: { pendingDraft != nil }, set: { if !$0 { pendingDraft = nil } }),
                            presenting: pendingDraft) { draft in
            ForEach(duplicates.prefix(3), id: \.card.id) { match in
                Button("Add to \(match.card.displayName)") { Task { await add(draft, to: match.card.id) } }
            }
            Button("Create New Contact Anyway") { Task { await create(draft) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text(duplicates.first.map { "\($0.card.displayName): \($0.match.reasons.joined(separator: ", "))" } ?? "")
        }
    }

    // MARK: - Logic

    private func results(for entry: QuickEntry) -> [ContactCard] {
        let found: [ContactCard] = switch entry {
        case .empty: store.cards
        case .action(_, let q): store.search(q)
        case .contact: store.search(query)
        }
        return compact ? Array(found.prefix(8)) : found
    }

    /// Offer to create a contact when what was typed isn't just a search for someone who exists.
    private func draftToOffer(_ entry: QuickEntry, results: [ContactCard]) -> (card: ContactCard, leftovers: [String])? {
        guard case .contact(let card, let leftovers) = entry, !card.isBlank else { return nil }
        return results.isEmpty || card.hasDetails ? (card, leftovers) : nil
    }

    private func icon(for entry: QuickEntry) -> String {
        switch entry {
        case .action(let action, _): action.systemImage
        default: "magnifyingglass"
        }
    }

    private func hint(for entry: QuickEntry, results: [ContactCard], draft: ContactCard?,
                      duplicates: [(card: ContactCard, match: PairMatch)]) -> String? {
        switch entry {
        case .empty:
            return compact ? "Try “Jane Doe jane@acme.com 555 123 4567” or “call Jane”" : nil
        case .action(let action, _):
            guard let target = actionTarget(results) else { return "No matching contact" }
            return ContactActions.isAvailable(action, for: target)
                ? "⏎ \(action.title) \(target.displayName)"
                : "\(target.displayName) has nothing to \(action.title.lowercased())"
        case .contact:
            guard draft != nil else { return nil }
            return duplicates.isEmpty ? "⏎ Create contact" : "⏎ Create or add to an existing contact"
        }
    }

    private func actionTarget(_ results: [ContactCard]) -> ContactCard? {
        results.first { $0.id == selection } ?? results.first
    }

    private func submit(_ entry: QuickEntry, results: [ContactCard], draft: ContactCard?,
                        duplicates: [(card: ContactCard, match: PairMatch)]) {
        switch entry {
        case .empty:
            break
        case .action(let action, _):
            if let target = actionTarget(results) { ContactActions.perform(action, for: target) }
        case .contact:
            if let draft {
                if duplicates.isEmpty {
                    Task { await create(draft) }
                } else {
                    pendingDraft = draft
                }
            } else if selection == nil {
                selection = results.first?.id
            }
        }
    }

    private func moveSelection(by delta: Int, in results: [ContactCard]) -> KeyPress.Result {
        guard !results.isEmpty else { return .ignored }
        let current = results.firstIndex { $0.id == selection } ?? (delta > 0 ? -1 : results.count)
        selection = results[min(max(current + delta, 0), results.count - 1)].id
        return .handled
    }

    private func create(_ draft: ContactCard) async {
        if let id = await store.create(draft) {
            query = ""
            selection = id
        }
    }

    private func add(_ draft: ContactCard, to id: String) async {
        await store.addDraft(draft, to: id)
        query = ""
        selection = id
    }
}

private struct DraftPreview: View {
    let draft: ContactCard
    let leftovers: [String]
    let duplicates: [(card: ContactCard, match: PairMatch)]
    let onCreate: () -> Void
    let onAddTo: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("New Contact").font(.caption).foregroundStyle(.secondary)
                    Text(draft.displayName).font(.headline)
                }
                Spacer()
                Button("Create", systemImage: "plus", action: onCreate)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            CardFieldsView(card: draft)
            if !leftovers.isEmpty {
                Text("Not recognized: \(leftovers.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if !duplicates.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Possible duplicate", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                    ForEach(duplicates.prefix(3), id: \.card.id) { item in
                        HStack {
                            ContactRow(card: item.card)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                ConfidenceBadge(confidence: item.match.confidence)
                                Text(item.match.reasons.joined(separator: " · "))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Button("Add Here") { onAddTo(item.card.id) }
                                .controlSize(.small)
                        }
                    }
                }
                .padding(8)
                .background(.orange.opacity(0.08), in: .rect(cornerRadius: 8))
            }
        }
        .padding(12)
    }
}
