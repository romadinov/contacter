import AppKit
import ContacterCore
import Foundation

/// Opens the system handler (Phone/FaceTime, Mail, Messages, Maps) for a contact action.
enum ContactActions {
    static func isAvailable(_ action: QuickAction, for card: ContactCard) -> Bool {
        url(for: action, card: card) != nil
    }

    static func url(for action: QuickAction, card: ContactCard) -> URL? {
        let phone = card.phones.first.map { $0.value.filter { $0.isNumber || $0 == "+" } }
        let email = card.emails.first?.value
        switch action {
        case .call:
            return phone.flatMap { URL(string: "tel:\($0)") }
        case .facetime:
            return (phone ?? email).flatMap { URL(string: "facetime:\($0)") }
        case .message:
            return (phone ?? email).flatMap { URL(string: "sms:\($0)") }
        case .email:
            return email.flatMap { URL(string: "mailto:\($0)") }
        case .map:
            guard let address = card.addresses.first?.singleLine, !address.isEmpty else { return nil }
            var components = URLComponents(string: "maps://")!
            components.queryItems = [URLQueryItem(name: "q", value: address)]
            return components.url
        }
    }

    @MainActor
    static func perform(_ action: QuickAction, for card: ContactCard) {
        guard let url = url(for: action, card: card) else { return }
        NSWorkspace.shared.open(url)
    }

    @MainActor
    static func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
