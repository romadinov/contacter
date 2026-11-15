import Foundation
import Testing
@testable import ContacterCore

@Suite struct QuickEntryParserTests {
    private func card(_ input: String) -> (ContactCard, [String]) {
        guard case .contact(let card, let leftovers) = QuickEntryParser.parse(input) else {
            Issue.record("Expected a contact for \(input)")
            return (ContactCard(), [])
        }
        return (card, leftovers)
    }

    @Test func fullLine() {
        let (c, leftovers) = card("Jane Doe, CEO at Acme Inc jane@acme.com work +1 415 555 0100 @janed https://jane.dev bday Apr 12 1990")
        #expect(c.givenName == "Jane")
        #expect(c.familyName == "Doe")
        #expect(c.jobTitle == "CEO")
        #expect(c.organization == "Acme Inc")
        #expect(c.emails == [LabeledValue(label: "work", value: "jane@acme.com")])
        #expect(c.phones.first?.label == "work")
        #expect(Normalize.phone(c.phones.first?.value ?? "") == Normalize.phone("4155550100"))
        #expect(c.socialProfiles == [SocialProfile(service: "Twitter", username: "janed")])
        #expect(c.urls.first?.value == "https://jane.dev")
        #expect(c.birthday == DateComponents(year: 1990, month: 4, day: 12))
        #expect(leftovers.isEmpty)
    }

    @Test func withoutCommas() {
        let (c, _) = card("john appleseed Apple Inc engineer john@apple.com")
        #expect(c.givenName == "John")
        #expect(c.familyName == "Appleseed")
        #expect(c.organization == "Apple Inc")
        #expect(c.jobTitle == "engineer")
    }

    @Test func middleInitialAndParticle() {
        let (a, _) = card("John F. Kennedy")
        #expect(a.givenName == "John")
        #expect(a.middleName == "F.")
        #expect(a.familyName == "Kennedy")
        let (b, _) = card("Ludwig van Beethoven")
        #expect(b.givenName == "Ludwig")
        #expect(b.familyName == "van Beethoven")
    }

    @Test func nameAndCompanyWithoutSuffix() {
        let (c, _) = card("Sarah Connor Cyberdyne 555 222 3333")
        #expect(c.givenName == "Sarah")
        #expect(c.familyName == "Connor")
        #expect(c.organization == "Cyberdyne")
        #expect(c.phones.first?.label == "mobile")
    }

    @Test func companyOnly() {
        let (c, _) = card("Globex Corporation info@globex.com")
        #expect(c.organization == "Globex Corporation")
        #expect(c.givenName.isEmpty)
    }

    @Test func socialServices() {
        let (c, _) = card("Linus Torvalds github torvalds linkedin: linus")
        #expect(c.socialProfiles.contains(SocialProfile(service: "GitHub", username: "torvalds")))
        #expect(c.socialProfiles.contains(SocialProfile(service: "LinkedIn", username: "linus")))
        #expect(c.familyName == "Torvalds")
    }

    @Test func actions() {
        #expect(QuickEntryParser.parse("call Jane") == .action(.call, query: "Jane"))
        #expect(QuickEntryParser.parse("email jane doe") == .action(.email, query: "jane doe"))
        if case .action = QuickEntryParser.parse("Call Center Inc 555 123 4567") {
            Issue.record("A contact with a phone number is not a command")
        }
    }

    @Test func dates() {
        #expect(QuickEntryParser.parseDate("12/25") == DateComponents(month: 12, day: 25))
        #expect(QuickEntryParser.parseDate("1985-07-03") == DateComponents(year: 1985, month: 7, day: 3))
        #expect(QuickEntryParser.parseDate("March 3rd") == DateComponents(month: 3, day: 3))
    }

    @Test func empty() {
        #expect(QuickEntryParser.parse("   ") == .empty)
    }
}
