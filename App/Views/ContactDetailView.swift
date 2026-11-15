import ContacterCore
import SwiftUI

struct ContactDetailView: View {
    @Environment(ContactStore.self) private var store
    let contactID: String
    var onReviewDuplicates: ((String) -> Void)?

    @State private var isEditing = false
    @State private var confirmDelete = false

    var body: some View {
        if let card = store.card(id: contactID) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header(card)
                    actionBar(card)
                    if let group = store.duplicateGroup(containing: contactID) {
                        duplicateBanner(group, card: card)
                    }
                    fields(card)
                }
                .padding(20)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toolbar {
                ToolbarItemGroup {
                    Button("Edit", systemImage: "pencil") { isEditing = true }
                        .keyboardShortcut("e")
                    Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
                }
            }
            .sheet(isPresented: $isEditing) {
                ContactEditorView(original: card)
            }
            .confirmationDialog("Delete \(card.displayName)?", isPresented: $confirmDelete) {
                Button("Delete", role: .destructive) { Task { await store.delete(ids: [contactID]) } }
            } message: {
                Text("A vCard backup is saved before deleting.")
            }
        } else {
            ContentUnavailableView("No Contact Selected", systemImage: "person.crop.circle")
        }
    }

    private func header(_ card: ContactCard) -> some View {
        HStack(spacing: 16) {
            AvatarView(id: card.id, initials: card.initials, size: 72)
            VStack(alignment: .leading, spacing: 3) {
                Text(card.displayName).font(.title.weight(.semibold)).textSelection(.enabled)
                if !card.nickname.isEmpty {
                    Text("“\(card.nickname)”").foregroundStyle(.secondary)
                }
                let role = [card.jobTitle, card.department, card.isCompany ? "" : card.organization].filter { !$0.isEmpty }
                if !role.isEmpty {
                    Text(role.joined(separator: " · ")).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
        }
    }

    private func actionBar(_ card: ContactCard) -> some View {
        HStack(spacing: 8) {
            ForEach(QuickAction.allCases, id: \.self) { action in
                Button {
                    ContactActions.perform(action, for: card)
                } label: {
                    Label(action.title, systemImage: action.systemImage)
                        .labelStyle(.verticalIconTitle)
                }
                .disabled(!ContactActions.isAvailable(action, for: card))
            }
        }
        .buttonStyle(.bordered)
    }

    private func duplicateBanner(_ group: DuplicateGroup, card: ContactCard) -> some View {
        let others = group.memberIDs.filter { $0 != card.id }.compactMap { store.card(id: $0)?.displayName }
        return HStack {
            Image(systemName: "person.2.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Possible duplicate of \(others.formatted(.list(type: .and)))").font(.callout.weight(.medium))
                Text(group.reasons.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let onReviewDuplicates {
                Button("Review") { onReviewDuplicates(group.id) }
            }
        }
        .padding(10)
        .background(.orange.opacity(0.1), in: .rect(cornerRadius: 8))
    }

    @ViewBuilder
    private func fields(_ card: ContactCard) -> some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
            ForEach(card.phones, id: \.self) { item in
                FieldRow(label: label(item.label, "phone"), value: item.value) {
                    ContactActions.perform(.call, for: ContactCard(phones: [item]))
                }
            }
            ForEach(card.emails, id: \.self) { item in
                FieldRow(label: label(item.label, "email"), value: item.value) {
                    ContactActions.perform(.email, for: ContactCard(emails: [item]))
                }
            }
            ForEach(card.urls, id: \.self) { item in
                FieldRow(label: label(item.label, "url"), value: item.value) {
                    let string = item.value.contains("://") ? item.value : "https://" + item.value
                    if let url = URL(string: string) { NSWorkspace.shared.open(url) }
                }
            }
            ForEach(card.socialProfiles, id: \.self) { item in
                FieldRow(label: item.service.lowercased(), value: "@" + item.username, action: nil)
            }
            ForEach(card.addresses, id: \.self) { item in
                FieldRow(label: label(item.label, "address"), value: item.singleLine) {
                    ContactActions.perform(.map, for: ContactCard(addresses: [item]))
                }
            }
            if let birthday = card.birthday {
                FieldRow(label: "birthday", value: BirthdayFormat.string(birthday), action: nil)
            }
        }
    }

    private func label(_ raw: String?, _ fallback: String) -> String {
        let l = ContactMapping.displayLabel(raw)
        return l.isEmpty ? fallback : l
    }
}

private struct FieldRow: View {
    let label: String
    let value: String
    let action: (() -> Void)?

    var body: some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Group {
                if let action {
                    Button(value, action: action).buttonStyle(.link)
                } else {
                    Text(value).textSelection(.enabled)
                }
            }
            .contextMenu {
                Button("Copy") { ContactActions.copy(value) }
            }
        }
    }
}

struct VerticalIconTitleLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 3) {
            configuration.icon.font(.title3)
            configuration.title.font(.caption2)
        }
        .frame(width: 58, height: 36)
    }
}

extension LabelStyle where Self == VerticalIconTitleLabelStyle {
    static var verticalIconTitle: Self { .init() }
}
