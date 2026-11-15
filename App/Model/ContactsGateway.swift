import AppKit
import Contacts
import ContacterCore
import Foundation

struct ContactSnapshot: Sendable {
    var cards: [ContactCard]
    var thumbnails: [String: Data]
}

enum GatewayError: LocalizedError {
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .notFound(let id): "The contact \(id) no longer exists."
        }
    }
}

/// All `CNContactStore` work. Runs off the main actor; each call makes its own store instance.
enum ContactsGateway {
    static func authorizationStatus() -> CNAuthorizationStatus {
        CNContactStore.authorizationStatus(for: .contacts)
    }

    static func requestAccess() async throws -> Bool {
        try await CNContactStore().requestAccess(for: .contacts)
    }

    @concurrent
    static func fetchAll() async throws -> ContactSnapshot {
        let store = CNContactStore()
        let request = CNContactFetchRequest(keysToFetch: ContactMapping.keys)
        request.unifyResults = true
        var cards: [ContactCard] = []
        var thumbnails: [String: Data] = [:]
        try store.enumerateContacts(with: request) { contact, _ in
            cards.append(ContactMapping.card(from: contact))
            if let data = contact.thumbnailImageData { thumbnails[contact.identifier] = data }
        }
        return ContactSnapshot(cards: cards, thumbnails: thumbnails)
    }

    @concurrent
    static func create(_ card: ContactCard) async throws -> String {
        let store = CNContactStore()
        let contact = CNMutableContact()
        ContactMapping.apply(card, to: contact)
        let save = CNSaveRequest()
        save.add(contact, toContainerWithIdentifier: nil)
        try store.execute(save)
        return contact.identifier
    }

    @concurrent
    static func update(_ card: ContactCard) async throws {
        let store = CNContactStore()
        let contact = try mutableContact(card.id, in: store)
        ContactMapping.apply(card, to: contact)
        let save = CNSaveRequest()
        save.update(contact)
        try store.execute(save)
    }

    @concurrent
    static func delete(ids: [String], backupTo directory: URL) async throws -> URL {
        let store = CNContactStore()
        let backup = try writeBackup(ids: ids, store: store, directory: directory, reason: "delete")
        let save = CNSaveRequest()
        for id in ids { save.delete(try mutableContact(id, in: store)) }
        try store.execute(save)
        return backup
    }

    /// Writes `merged` onto the primary contact and deletes the others, atomically, after backing all of them up.
    @concurrent
    static func merge(_ merged: ContactCard, removing others: [String], backupTo directory: URL) async throws -> URL {
        let store = CNContactStore()
        let backup = try writeBackup(ids: [merged.id] + others, store: store, directory: directory, reason: "merge")
        let primary = try mutableContact(merged.id, in: store)
        ContactMapping.apply(merged, to: primary)

        let save = CNSaveRequest()
        var removed: [CNMutableContact] = []
        for id in others { removed.append(try mutableContact(id, in: store)) }
        if primary.imageData == nil, let image = removed.lazy.compactMap(\.imageData).first {
            primary.imageData = image
        }
        save.update(primary)
        removed.forEach(save.delete)
        try store.execute(save)
        return backup
    }

    /// Reverses a merge: deletes the surviving contact and re-adds every contact from the pre-merge backup.
    /// Returns the identifiers of the restored contacts (Contacts assigns new ones).
    @concurrent
    static func undoMerge(survivorID: String, backup: URL) async throws -> [String] {
        let store = CNContactStore()
        let originals = try CNContactVCardSerialization.contacts(with: Data(contentsOf: backup))
        let save = CNSaveRequest()
        if let survivor = try? mutableContact(survivorID, in: store) { save.delete(survivor) }
        let restored = originals.map { $0.mutableCopy() as! CNMutableContact }
        for contact in restored { save.add(contact, toContainerWithIdentifier: nil) }
        try store.execute(save)
        return restored.map(\.identifier)
    }

    private static func mutableContact(_ id: String, in store: CNContactStore) throws -> CNMutableContact {
        let keys = ContactMapping.keys + [CNContactImageDataKey as CNKeyDescriptor]
        guard let contact = try? store.unifiedContact(withIdentifier: id, keysToFetch: keys) else {
            throw GatewayError.notFound(id)
        }
        return contact.mutableCopy() as! CNMutableContact
    }

    /// Every destructive operation first exports the affected contacts as a vCard you can re-import into Contacts.
    private static func writeBackup(ids: [String], store: CNContactStore, directory: URL, reason: String) throws -> URL {
        let predicate = CNContact.predicateForContacts(withIdentifiers: ids)
        let contacts = try store.unifiedContacts(matching: predicate,
                                                 keysToFetch: [CNContactVCardSerialization.descriptorForRequiredKeys()])
        let data = try CNContactVCardSerialization.data(with: contacts)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)
            .timeSeparator(.omitted).dateTimeSeparator(.standard))
        let url = directory.appending(path: "\(stamp)-\(reason).vcf")
        try data.write(to: url, options: .atomic)
        return url
    }
}
