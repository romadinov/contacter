import Foundation

/// A labeled value such as a phone number, email address, URL or social handle.
public struct LabeledValue: Hashable, Sendable, Codable {
    public var label: String?
    public var value: String

    public init(label: String? = nil, value: String) {
        self.label = label
        self.value = value
    }
}

public struct PostalAddress: Hashable, Sendable, Codable {
    public var label: String?
    public var street: String
    public var city: String
    public var state: String
    public var postalCode: String
    public var country: String

    public init(label: String? = nil, street: String = "", city: String = "", state: String = "",
                postalCode: String = "", country: String = "") {
        self.label = label
        self.street = street
        self.city = city
        self.state = state
        self.postalCode = postalCode
        self.country = country
    }

    public var isEmpty: Bool {
        [street, city, state, postalCode, country].allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    public var singleLine: String {
        [street.replacingOccurrences(of: "\n", with: ", "), city, state, postalCode, country]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

public struct SocialProfile: Hashable, Sendable, Codable {
    public var service: String
    public var username: String

    public init(service: String, username: String) {
        self.service = service
        self.username = username
    }
}

/// A framework-independent snapshot of a contact. The app maps `CNContact` to and from this type;
/// everything in this package (parsing, duplicate detection, merging) works on it.
public struct ContactCard: Identifiable, Hashable, Sendable, Codable {
    public var id: String
    public var givenName: String
    public var middleName: String
    public var familyName: String
    public var nickname: String
    public var organization: String
    public var jobTitle: String
    public var department: String
    public var phones: [LabeledValue]
    public var emails: [LabeledValue]
    public var urls: [LabeledValue]
    public var addresses: [PostalAddress]
    public var socialProfiles: [SocialProfile]
    public var birthday: DateComponents?
    public var hasImage: Bool

    public init(id: String = UUID().uuidString, givenName: String = "", middleName: String = "",
                familyName: String = "", nickname: String = "", organization: String = "",
                jobTitle: String = "", department: String = "", phones: [LabeledValue] = [],
                emails: [LabeledValue] = [], urls: [LabeledValue] = [], addresses: [PostalAddress] = [],
                socialProfiles: [SocialProfile] = [], birthday: DateComponents? = nil, hasImage: Bool = false) {
        self.id = id
        self.givenName = givenName
        self.middleName = middleName
        self.familyName = familyName
        self.nickname = nickname
        self.organization = organization
        self.jobTitle = jobTitle
        self.department = department
        self.phones = phones
        self.emails = emails
        self.urls = urls
        self.addresses = addresses
        self.socialProfiles = socialProfiles
        self.birthday = birthday
        self.hasImage = hasImage
    }

    public var personName: String {
        [givenName, middleName, familyName].filter { !$0.isEmpty }.joined(separator: " ")
    }

    public var isCompany: Bool { personName.isEmpty && !organization.isEmpty }

    public var displayName: String {
        if !personName.isEmpty { return personName }
        if !organization.isEmpty { return organization }
        if let email = emails.first?.value { return email }
        if let phone = phones.first?.value { return phone }
        return "No Name"
    }

    public var subtitle: String {
        if isCompany { return emails.first?.value ?? phones.first?.value ?? "" }
        let role = [jobTitle, organization].filter { !$0.isEmpty }
        if !role.isEmpty { return role.joined(separator: " · ") }
        return emails.first?.value ?? phones.first?.value ?? ""
    }

    public var initials: String {
        let parts = isCompany ? [organization] : [givenName, familyName]
        let letters = parts.compactMap { $0.first }.map(String.init).joined()
        return letters.isEmpty ? String(displayName.prefix(1)).uppercased() : letters.uppercased()
    }

    /// How much information the card carries; used to choose the default merge target.
    public var richness: Int {
        let singles = [givenName, middleName, familyName, nickname, organization, jobTitle, department]
            .filter { !$0.isEmpty }.count
        return singles + 2 * (phones.count + emails.count) + urls.count + 2 * addresses.count
            + socialProfiles.count + (birthday == nil ? 0 : 2) + (hasImage ? 3 : 0)
    }

    public var isBlank: Bool {
        personName.isEmpty && organization.isEmpty && nickname.isEmpty && phones.isEmpty && emails.isEmpty
            && urls.isEmpty && addresses.isEmpty && socialProfiles.isEmpty && birthday == nil
    }

    /// Everything searchable, normalized once.
    public var searchText: String {
        var parts = [personName, nickname, organization, jobTitle, department]
        parts += emails.map(\.value)
        parts += socialProfiles.map(\.username)
        var text = Normalize.text(parts.joined(separator: " "))
        let digits = phones.map { $0.value.filter(\.isNumber) }.joined(separator: " ")
        if !digits.isEmpty { text += " " + digits }
        return text
    }
}
