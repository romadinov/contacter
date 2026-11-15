import Foundation
import Testing
@testable import ContacterCore

@Suite struct NormalizeTests {
    @Test func phonesMatchAcrossFormats() {
        #expect(Normalize.phone("+61 412 345 678") == Normalize.phone("0412 345 678"))
        #expect(Normalize.phone("+1 (555) 123-4567") == Normalize.phone("555.123.4567"))
        #expect(Normalize.phone("555-1234 ext. 99") == Normalize.phone("5551234"))
        #expect(Normalize.phone("123") == nil)
    }

    @Test func emailsIgnoreCaseTagsAndGmailDots() {
        #expect(Normalize.email("Jane.Doe+news@GMail.com") == "janedoe@gmail.com")
        #expect(Normalize.email("jane.doe@acme.com") == "jane.doe@acme.com")
        #expect(Normalize.email("not an email") == nil)
    }

    @Test func textFoldsDiacriticsAndPunctuation() {
        #expect(Normalize.text("  José  O'Brien-Smith ") == "jose obrien smith")
    }
}

@Suite struct ScorerTests {
    @Test func sameEmailAndNameIsHighConfidence() {
        let a = ContactCard(id: "a", givenName: "Jane", familyName: "Doe", emails: [.init(value: "jane@acme.com")])
        let b = ContactCard(id: "b", givenName: "jane", familyName: "doe", emails: [.init(value: "JANE@acme.com")])
        #expect(DuplicateScorer.score(a, b).confidence == .high)
    }

    @Test func nicknameAndPhone() {
        let a = ContactCard(id: "a", givenName: "Robert", familyName: "Smith", phones: [.init(value: "+1 415 555 0100")])
        let b = ContactCard(id: "b", givenName: "Bob", familyName: "Smith", phones: [.init(value: "(415) 555-0100")])
        let m = DuplicateScorer.score(a, b)
        #expect(m.confidence == .high)
        #expect(m.reasons.contains("Same name (nickname)"))
    }

    @Test func householdSharingALandlineIsNotADuplicate() {
        let a = ContactCard(id: "a", givenName: "John", familyName: "Smith", phones: [.init(value: "555 123 4567")])
        let b = ContactCard(id: "b", givenName: "Mary", familyName: "Smith", phones: [.init(value: "555 123 4567")])
        #expect(DuplicateScorer.score(a, b).score < DuplicateScorer.threshold)
    }

    @Test func sharedInfoMailboxIsNotADuplicate() {
        let a = ContactCard(id: "a", givenName: "John", familyName: "Smith", emails: [.init(value: "info@acme.com")])
        let b = ContactCard(id: "b", givenName: "Priya", familyName: "Patel", emails: [.init(value: "info@acme.com")])
        #expect(DuplicateScorer.score(a, b).score < DuplicateScorer.threshold)
    }

    @Test func differentBirthdaysVeto() {
        let a = ContactCard(id: "a", givenName: "John", familyName: "Smith", birthday: DateComponents(month: 1, day: 2))
        let b = ContactCard(id: "b", givenName: "John", familyName: "Smith", birthday: DateComponents(month: 5, day: 9))
        #expect(DuplicateScorer.score(a, b).score < DuplicateScorer.threshold)
    }

    @Test func typoInNameWithSameCompany() {
        let a = ContactCard(id: "a", givenName: "Jonathan", familyName: "Appleseed", organization: "Apple")
        let b = ContactCard(id: "b", givenName: "Jonathon", familyName: "Appleseed", organization: "Apple Inc")
        #expect(DuplicateScorer.score(a, b).score >= DuplicateScorer.threshold)
    }

    @Test func swappedNameOrder() {
        let a = ContactCard(id: "a", givenName: "Wei", familyName: "Zhang", emails: [.init(value: "wz@x.com")])
        let b = ContactCard(id: "b", givenName: "Zhang", familyName: "Wei")
        #expect(DuplicateScorer.score(a, b).reasons.contains("Same name"))
    }

    @Test func initialMatchesFullName() {
        let a = ContactCard(id: "a", givenName: "J", familyName: "Appleseed", phones: [.init(value: "0400 000 001")])
        let b = ContactCard(id: "b", givenName: "John", familyName: "Appleseed", phones: [.init(value: "+61 400 000 001")])
        #expect(DuplicateScorer.score(a, b).confidence == .high)
    }
}

@Suite struct FinderTests {
    @Test func clustersTransitiveDuplicates() {
        let cards = [
            ContactCard(id: "1", givenName: "Jane", familyName: "Doe", emails: [.init(value: "jane@acme.com")]),
            ContactCard(id: "2", givenName: "Jane", familyName: "Doe", phones: [.init(value: "555 111 2222")],
                        emails: [.init(value: "jane@acme.com")]),
            ContactCard(id: "3", givenName: "J.", familyName: "Doe", phones: [.init(value: "(555) 111-2222")]),
            ContactCard(id: "4", givenName: "Mark", familyName: "Twain"),
            ContactCard(id: "5", givenName: "Mark", familyName: "Twain"),
            ContactCard(id: "6", givenName: "Ada", familyName: "Lovelace"),
        ]
        let groups = DuplicateFinder.findGroups(in: cards)
        #expect(groups.map(\.memberIDs).contains(["1", "2", "3"]))
        #expect(groups.map(\.memberIDs).contains(["4", "5"]))
        #expect(!groups.flatMap(\.memberIDs).contains("6"))
    }

    @Test func ignoredPairsAreSkipped() {
        let cards = [
            ContactCard(id: "4", givenName: "Mark", familyName: "Twain"),
            ContactCard(id: "5", givenName: "Mark", familyName: "Twain"),
        ]
        #expect(DuplicateFinder.findGroups(in: cards, ignoring: [ContactPair("5", "4")]).isEmpty)
    }

    @Test func scalesToThousandsOfContacts() {
        var cards: [ContactCard] = []
        for i in 0..<5000 {
            cards.append(ContactCard(id: "\(i)", givenName: "John", familyName: "Person\(i)",
                                     phones: [.init(value: "+1 415 \(1_000_000 + i)")]))
        }
        cards.append(ContactCard(id: "dup", givenName: "John", familyName: "Person42", phones: [.init(value: "415 1000042")]))
        let start = Date()
        let groups = DuplicateFinder.findGroups(in: cards)
        #expect(Date().timeIntervalSince(start) < 10)
        #expect(groups.map(\.memberIDs).contains(["42", "dup"]))
    }

    @Test func entryMatchesExisting() {
        let index = DuplicateIndex([
            ContactCard(id: "x", givenName: "Jane", familyName: "Doe", emails: [.init(value: "jane@acme.com")]),
        ])
        let draft = ContactCard(id: "draft", givenName: "Jane", familyName: "Doe", phones: [.init(value: "555 123 4567")])
        #expect(index.matches(for: draft).first?.card.id == "x")
    }
}

@Suite struct MergerTests {
    @Test func unionsAndFillsGaps() {
        let a = ContactCard(id: "a", givenName: "J", familyName: "Doe", phones: [.init(label: "mobile", value: "555 111 2222")],
                            emails: [.init(value: "jane@acme.com")])
        let b = ContactCard(id: "b", givenName: "Jane", familyName: "Doe", organization: "Acme",
                            phones: [.init(label: "work", value: "(555) 111-2222"), .init(value: "555 999 0000")],
                            emails: [.init(value: "Jane@Acme.com"), .init(value: "jane@gmail.com")],
                            birthday: DateComponents(month: 3, day: 4))
        let merged = ContactMerger.merge([a, b], primaryID: "a")
        #expect(merged.id == "a")
        #expect(merged.givenName == "Jane")
        #expect(merged.organization == "Acme")
        #expect(merged.phones.map(\.value) == ["555 111 2222", "555 999 0000"])
        #expect(merged.phones.first?.label == "mobile")
        #expect(merged.emails.map(\.value) == ["jane@acme.com", "jane@gmail.com"])
        #expect(merged.birthday?.month == 3)
    }

    @Test func primaryKeepsItsValues() {
        let a = ContactCard(id: "a", givenName: "Jane", familyName: "Doe", organization: "Acme")
        let b = ContactCard(id: "b", givenName: "Janet", familyName: "Doe", organization: "Globex")
        let merged = ContactMerger.merge([a, b], primaryID: "a")
        #expect(merged.givenName == "Jane")
        #expect(merged.organization == "Acme")
    }

    @Test func defaultPrimaryIsRichest() {
        let thin = ContactCard(id: "a", givenName: "Jane")
        let rich = ContactCard(id: "b", givenName: "Jane", familyName: "Doe", emails: [.init(value: "j@x.com")])
        #expect(ContactMerger.defaultPrimary(of: [thin, rich])?.id == "b")
    }
}
