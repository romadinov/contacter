import Foundation
import Testing
@testable import ContacterCore

@Suite struct AutoMergePolicyTests {
    private func group(_ cards: [ContactCard]) -> (DuplicateGroup, [String: ContactCard]) {
        let groups = DuplicateFinder.findGroups(in: cards)
        #expect(groups.count == 1)
        return (groups[0], Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) }))
    }

    @Test func sameNameAndEmailIsEligible() {
        let (g, cards) = group([
            ContactCard(id: "a", givenName: "Jane", familyName: "Doe", emails: [.init(value: "jane@acme.com")]),
            ContactCard(id: "b", givenName: "Jane", familyName: "Doe", phones: [.init(value: "555 111 2222")],
                        emails: [.init(value: "Jane@Acme.com")]),
        ])
        #expect(AutoMergePolicy().isEligible(g, cards: cards))
    }

    @Test func nameOnlyIsNeverEligible() {
        let (g, cards) = group([
            ContactCard(id: "a", givenName: "Mark", familyName: "Twain", organization: "Acme",
                        birthday: DateComponents(month: 1, day: 1)),
            ContactCard(id: "b", givenName: "Mark", familyName: "Twain", organization: "Acme",
                        birthday: DateComponents(month: 1, day: 1)),
        ])
        #expect(AutoMergePolicy(strictness: .standard).verdict(for: g, cards: cards) == .noSharedIdentifier("a", "b"))
    }

    @Test func strictRejectsWhatStandardAccepts() {
        // Shared phone + nickname = 80: high confidence, but not strict.
        let (g, cards) = group([
            ContactCard(id: "a", givenName: "Robert", familyName: "Smith", phones: [.init(value: "+1 415 555 0100")]),
            ContactCard(id: "b", givenName: "Bob", familyName: "Smith", phones: [.init(value: "(415) 555-0100")]),
        ])
        #expect(AutoMergePolicy(strictness: .standard).isEligible(g, cards: cards))
        #expect(!AutoMergePolicy(strictness: .strict).isEligible(g, cards: cards))
    }

    @Test func chainWithWeakEndsIsRejected() {
        // a≈b by email, b≈c by phone, but a and c share nothing directly.
        let (g, cards) = group([
            ContactCard(id: "a", givenName: "Jane", familyName: "Doe", emails: [.init(value: "jane@acme.com")]),
            ContactCard(id: "b", givenName: "Jane", familyName: "Doe", phones: [.init(value: "555 111 2222")],
                        emails: [.init(value: "jane@acme.com")]),
            ContactCard(id: "c", givenName: "Jane", familyName: "Doe", phones: [.init(value: "555 111 2222")]),
        ])
        #expect(g.memberIDs.count == 3)
        #expect(!AutoMergePolicy(strictness: .standard).isEligible(g, cards: cards))
    }

    @Test func largeGroupsAreLeftForReview() {
        let cards = (0..<4).map {
            ContactCard(id: "\($0)", givenName: "Jane", familyName: "Doe", emails: [.init(value: "jane@acme.com")])
        }
        let (g, byID) = group(cards)
        #expect(AutoMergePolicy(maxGroupSize: 3).verdict(for: g, cards: byID) == .tooLarge)
        #expect(AutoMergePolicy(maxGroupSize: 4).isEligible(g, cards: byID))
    }

    @Test func missingContactIsRejected() {
        let (g, cards) = group([
            ContactCard(id: "a", givenName: "Jane", familyName: "Doe", emails: [.init(value: "jane@acme.com")]),
            ContactCard(id: "b", givenName: "Jane", familyName: "Doe", emails: [.init(value: "jane@acme.com")]),
        ])
        #expect(AutoMergePolicy().verdict(for: g, cards: cards.filter { $0.key == "a" }) == .missingContact)
    }
}
