import ContacterCore
import SwiftUI

/// Row model for editable multi-value fields: gives each row a stable identity while editing.
private struct EditableValue: Identifiable {
    let id = UUID()
    var label: String
    var value: String
}

private struct EditableAddress: Identifiable {
    let id = UUID()
    var address: PostalAddress
}

private struct EditableSocial: Identifiable {
    let id = UUID()
    var profile: SocialProfile
}

/// Edits an existing contact, or creates a new one when `original` isn't in the store yet.
struct ContactEditorView: View {
    @Environment(ContactStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let original: ContactCard
    var onCreated: ((String) -> Void)?

    @State private var card: ContactCard
    @State private var phones: [EditableValue]
    @State private var emails: [EditableValue]
    @State private var urls: [EditableValue]
    @State private var addresses: [EditableAddress]
    @State private var socials: [EditableSocial]
    @State private var birthday: String
    @State private var isSaving = false

    init(original: ContactCard, onCreated: ((String) -> Void)? = nil) {
        self.original = original
        self.onCreated = onCreated
        _card = State(initialValue: original)
        _phones = State(initialValue: original.phones.map { EditableValue(label: ContactMapping.displayLabel($0.label), value: $0.value) })
        _emails = State(initialValue: original.emails.map { EditableValue(label: ContactMapping.displayLabel($0.label), value: $0.value) })
        _urls = State(initialValue: original.urls.map { EditableValue(label: ContactMapping.displayLabel($0.label), value: $0.value) })
        _addresses = State(initialValue: original.addresses.map { EditableAddress(address: $0) })
        _socials = State(initialValue: original.socialProfiles.map { EditableSocial(profile: $0) })
        _birthday = State(initialValue: original.birthday.map(BirthdayFormat.string) ?? "")
    }

    private var isNew: Bool { store.card(id: original.id) == nil }
    private var birthdayIsValid: Bool { birthday.isEmpty || QuickEntryParser.parseDate(birthday) != nil }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Name") {
                    TextField("First", text: $card.givenName)
                    TextField("Middle", text: $card.middleName)
                    TextField("Last", text: $card.familyName)
                    TextField("Nickname", text: $card.nickname)
                }
                Section("Work") {
                    TextField("Company", text: $card.organization)
                    TextField("Job Title", text: $card.jobTitle)
                    TextField("Department", text: $card.department)
                }
                LabeledValuesSection(title: "Phone", defaultLabel: "mobile", items: $phones)
                LabeledValuesSection(title: "Email", defaultLabel: "work", items: $emails)
                LabeledValuesSection(title: "URL", defaultLabel: "homepage", items: $urls)
                Section("Social") {
                    ForEach($socials) { $item in
                        HStack {
                            TextField("Service", text: $item.profile.service).frame(width: 110)
                            TextField("Username", text: $item.profile.username)
                            RemoveButton { socials.removeAll { $0.id == item.id } }
                        }
                    }
                    Button("Add Social Profile", systemImage: "plus") {
                        socials.append(EditableSocial(profile: SocialProfile(service: "Twitter", username: "")))
                    }
                }
                Section("Address") {
                    ForEach($addresses) { $item in
                        VStack(alignment: .leading) {
                            HStack {
                                TextField("Label", text: Binding($item.address.label, replacingNilWith: "")).frame(width: 110)
                                Spacer()
                                RemoveButton { addresses.removeAll { $0.id == item.id } }
                            }
                            TextField("Street", text: $item.address.street)
                            HStack {
                                TextField("City", text: $item.address.city)
                                TextField("State", text: $item.address.state)
                                TextField("ZIP", text: $item.address.postalCode).frame(width: 80)
                            }
                            TextField("Country", text: $item.address.country)
                        }
                    }
                    Button("Add Address", systemImage: "plus") {
                        addresses.append(EditableAddress(address: PostalAddress(label: "home")))
                    }
                }
                Section("Birthday") {
                    TextField("e.g. April 12 or 1990-04-12", text: $birthday)
                    if !birthdayIsValid {
                        Text("Can't read that date").font(.caption).foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Create" : "Save") { Task { await save() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSaving || !birthdayIsValid || assembled.isBlank)
            }
            .padding(12)
        }
        .frame(minWidth: 460, idealWidth: 500, minHeight: 520, idealHeight: 680)
    }

    private var assembled: ContactCard {
        var result = card
        result.phones = phones.filter { !$0.value.isEmpty }.map { LabeledValue(label: $0.label, value: $0.value) }
        result.emails = emails.filter { !$0.value.isEmpty }.map { LabeledValue(label: $0.label, value: $0.value) }
        result.urls = urls.filter { !$0.value.isEmpty }.map { LabeledValue(label: $0.label, value: $0.value) }
        result.addresses = addresses.map(\.address).filter { !$0.isEmpty }
        result.socialProfiles = socials.map(\.profile).filter { !$0.username.isEmpty }
        result.birthday = birthday.isEmpty ? nil : QuickEntryParser.parseDate(birthday)
        return result
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        if isNew {
            if let id = await store.create(assembled) { onCreated?(id) }
        } else {
            await store.update(assembled)
        }
        dismiss()
    }
}

private struct LabeledValuesSection: View {
    let title: String
    let defaultLabel: String
    @Binding var items: [EditableValue]

    var body: some View {
        Section(title) {
            ForEach($items) { $item in
                HStack {
                    Picker("Label", selection: $item.label) {
                        ForEach(Self.labels(including: item.label), id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                    TextField(title, text: $item.value)
                    RemoveButton { items.removeAll { $0.id == item.id } }
                }
            }
            Button("Add \(title)", systemImage: "plus") {
                items.append(EditableValue(label: defaultLabel, value: ""))
            }
        }
    }

    private static func labels(including current: String) -> [String] {
        let base = ContactMapping.editableLabels
        return base.contains(current) ? base : [current] + base
    }
}

private struct RemoveButton: View {
    let action: () -> Void

    var body: some View {
        Button("Remove", systemImage: "minus.circle.fill", action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .foregroundStyle(.red)
    }
}

private extension Binding where Value == String {
    init(_ source: Binding<String?>, replacingNilWith fallback: String) {
        self.init(get: { source.wrappedValue ?? fallback }, set: { source.wrappedValue = $0.isEmpty ? nil : $0 })
    }
}
