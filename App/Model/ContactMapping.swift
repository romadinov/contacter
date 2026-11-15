import Contacts
import ContacterCore
import Foundation

/// Converts between `CNContact` and the framework-free `ContactCard`.
enum ContactMapping {
    static var keys: [CNKeyDescriptor] {
        [
            CNContactGivenNameKey, CNContactMiddleNameKey, CNContactFamilyNameKey, CNContactNicknameKey,
            CNContactOrganizationNameKey, CNContactJobTitleKey, CNContactDepartmentNameKey,
            CNContactPhoneNumbersKey, CNContactEmailAddressesKey, CNContactUrlAddressesKey,
            CNContactPostalAddressesKey, CNContactSocialProfilesKey, CNContactBirthdayKey,
            CNContactImageDataAvailableKey, CNContactThumbnailImageDataKey, CNContactTypeKey,
        ] as [CNKeyDescriptor] + [CNContactFormatter.descriptorForRequiredKeys(for: .fullName)]
    }

    static func card(from c: CNContact) -> ContactCard {
        ContactCard(
            id: c.identifier,
            givenName: c.givenName,
            middleName: c.middleName,
            familyName: c.familyName,
            nickname: c.nickname,
            organization: c.organizationName,
            jobTitle: c.jobTitle,
            department: c.departmentName,
            phones: c.phoneNumbers.map { LabeledValue(label: $0.label, value: $0.value.stringValue) },
            emails: c.emailAddresses.map { LabeledValue(label: $0.label, value: $0.value as String) },
            urls: c.urlAddresses.map { LabeledValue(label: $0.label, value: $0.value as String) },
            addresses: c.postalAddresses.map {
                PostalAddress(label: $0.label, street: $0.value.street, city: $0.value.city, state: $0.value.state,
                              postalCode: $0.value.postalCode, country: $0.value.country)
            },
            socialProfiles: c.socialProfiles.map {
                SocialProfile(service: $0.value.service, username: $0.value.username)
            },
            birthday: c.birthday.map { DateComponents(year: $0.year == NSDateComponentUndefined ? nil : $0.year,
                                                      month: $0.month, day: $0.day) },
            hasImage: c.imageDataAvailable
        )
    }

    static func apply(_ card: ContactCard, to m: CNMutableContact) {
        m.givenName = card.givenName
        m.middleName = card.middleName
        m.familyName = card.familyName
        m.nickname = card.nickname
        m.organizationName = card.organization
        m.jobTitle = card.jobTitle
        m.departmentName = card.department
        m.contactType = card.isCompany ? .organization : .person
        m.phoneNumbers = card.phones.filter { !$0.value.isEmpty }.map {
            CNLabeledValue(label: cnLabel($0.label), value: CNPhoneNumber(stringValue: $0.value))
        }
        m.emailAddresses = card.emails.filter { !$0.value.isEmpty }.map {
            CNLabeledValue(label: cnLabel($0.label), value: $0.value as NSString)
        }
        m.urlAddresses = card.urls.filter { !$0.value.isEmpty }.map {
            CNLabeledValue(label: cnLabel($0.label), value: $0.value as NSString)
        }
        m.postalAddresses = card.addresses.filter { !$0.isEmpty }.map { a in
            let p = CNMutablePostalAddress()
            p.street = a.street
            p.city = a.city
            p.state = a.state
            p.postalCode = a.postalCode
            p.country = a.country
            return CNLabeledValue(label: cnLabel(a.label), value: p.copy() as! CNPostalAddress)
        }
        m.socialProfiles = card.socialProfiles.filter { !$0.username.isEmpty }.map {
            CNLabeledValue(label: nil, value: CNSocialProfile(urlString: nil, username: $0.username,
                                                               userIdentifier: nil, service: $0.service))
        }
        m.birthday = card.birthday.map { b in
            var c = DateComponents(month: b.month, day: b.day)
            c.year = b.year
            return c
        }
    }

    /// Maps the short labels used by the parser and editor to Contacts' built-in label constants.
    static func cnLabel(_ label: String?) -> String? {
        guard let label, !label.isEmpty else { return nil }
        if label.hasPrefix("_$!<") { return label }
        return switch label.lowercased() {
        case "mobile", "cell": CNLabelPhoneNumberMobile
        case "iphone": CNLabelPhoneNumberiPhone
        case "main": CNLabelPhoneNumberMain
        case "work fax": CNLabelPhoneNumberWorkFax
        case "home fax": CNLabelPhoneNumberHomeFax
        case "pager": CNLabelPhoneNumberPager
        case "work": CNLabelWork
        case "home": CNLabelHome
        case "school": CNLabelSchool
        case "other": CNLabelOther
        case "homepage": CNLabelURLAddressHomePage
        default: label
        }
    }

    static func displayLabel(_ label: String?) -> String {
        guard let label, !label.isEmpty else { return "" }
        return CNLabeledValue<NSString>.localizedString(forLabel: label)
    }

    static let editableLabels = ["mobile", "iPhone", "home", "work", "main", "school", "other", "homepage"]
}
