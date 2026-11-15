import Foundation

public enum ContactMerger {
    /// The card with the most information wins by default.
    public static func defaultPrimary(of cards: [ContactCard]) -> ContactCard? {
        cards.max { ($0.richness, $1.id) < ($1.richness, $0.id) }
    }

    /// Merges `cards` into the one whose id is `primaryID`. Scalar fields keep the primary's value unless it is
    /// empty or an abbreviation of another card's value ("J" → "John"); multi-value fields are unioned with
    /// duplicates (by normalized value) removed. The result keeps the primary's id.
    public static func merge(_ cards: [ContactCard], primaryID: String) -> ContactCard {
        guard var merged = cards.first(where: { $0.id == primaryID }) ?? cards.first else { return ContactCard() }
        let others = cards.filter { $0.id != merged.id }.sorted { $0.richness > $1.richness }

        for other in others {
            fill(&merged.givenName, from: other.givenName)
            fill(&merged.middleName, from: other.middleName)
            fill(&merged.familyName, from: other.familyName)
            fill(&merged.nickname, from: other.nickname)
            fill(&merged.organization, from: other.organization)
            fill(&merged.jobTitle, from: other.jobTitle)
            fill(&merged.department, from: other.department)
            merged.birthday = merged.birthday ?? other.birthday
            merged.hasImage = merged.hasImage || other.hasImage
        }

        let all = [merged] + others
        merged.phones = union(all.flatMap(\.phones)) { Normalize.phone($0.value) ?? $0.value }
        merged.emails = union(all.flatMap(\.emails)) { Normalize.email($0.value) ?? $0.value.lowercased() }
        merged.urls = union(all.flatMap(\.urls)) { Normalize.url($0.value) }
        merged.socialProfiles = union(all.flatMap(\.socialProfiles), key: Normalize.social)
        merged.addresses = union(all.flatMap(\.addresses).filter { !$0.isEmpty }, key: Normalize.address)
        return merged
    }

    /// Folds a freshly typed draft into an existing contact (used by quick entry's "add to existing").
    public static func absorb(_ draft: ContactCard, into existing: ContactCard) -> ContactCard {
        var draft = draft
        draft.id = UUID().uuidString
        return merge([existing, draft], primaryID: existing.id)
    }

    private static func fill(_ field: inout String, from candidate: String) {
        let current = field.trimmingCharacters(in: .whitespaces)
        let other = candidate.trimmingCharacters(in: .whitespaces)
        guard !other.isEmpty else { return }
        if current.isEmpty {
            field = other
            return
        }
        // "J." or "J" is an abbreviation of "John".
        let stem = current.hasSuffix(".") ? String(current.dropLast()) : current
        if stem.count <= 2, other.count > stem.count, Normalize.text(other).hasPrefix(Normalize.text(stem)) {
            field = other
        }
    }

    private static func union<T>(_ items: [T], key: (T) -> String) -> [T] {
        var seen = Set<String>()
        return items.filter { seen.insert(key($0)).inserted }
    }
}
