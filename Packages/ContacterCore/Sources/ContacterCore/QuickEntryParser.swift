import Foundation

public enum QuickAction: String, CaseIterable, Sendable {
    case call, email, message, facetime, map

    public var title: String {
        switch self {
        case .call: "Call"
        case .email: "Email"
        case .message: "Message"
        case .facetime: "FaceTime"
        case .map: "Map"
        }
    }

    public var systemImage: String {
        switch self {
        case .call: "phone"
        case .email: "envelope"
        case .message: "message"
        case .facetime: "video"
        case .map: "map"
        }
    }

    static let verbs: [String: QuickAction] = [
        "call": .call, "phone": .call, "ring": .call,
        "email": .email, "mail": .email, "e-mail": .email,
        "message": .message, "text": .message, "sms": .message, "imessage": .message,
        "facetime": .facetime, "ft": .facetime,
        "map": .map, "directions": .map,
    ]
}

public enum QuickEntry: Equatable, Sendable {
    case empty
    /// "call Jane" — perform an action on an existing contact matching `query`.
    case action(QuickAction, query: String)
    /// Free text describing a contact. `leftovers` are fragments the parser could not place.
    case contact(ContactCard, leftovers: [String])
}

/// Turns a single line like "Jane Doe, CEO at Acme Inc jane@acme.com work 555-123-4567 @jane bday Apr 12"
/// into a structured contact, the way Cardhop does.
public enum QuickEntryParser {
    public static func parse(_ input: String) -> QuickEntry {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }

        if let action = parseAction(trimmed) { return action }

        var text = trimmed
        var card = ContactCard(id: "draft")

        // Emails first so the link detector does not read them as mailto: URLs.
        for (match, label) in extract(#"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#, from: &text) {
            card.emails.append(LabeledValue(label: label ?? defaultEmailLabel(match), value: match))
        }

        if let bday = extractBirthday(from: &text) { card.birthday = bday }

        let services = #"twitter|x|instagram|insta|ig|linkedin|github|gh|facebook|fb|mastodon|threads|telegram|tg|bluesky|bsky"#
        for groups in extractGroups("(?i)\\b(\(services))\\s*:?\\s*@?([A-Za-z0-9_.\\-/]+)", from: &text) {
            card.socialProfiles.append(SocialProfile(service: serviceName(groups[1]), username: groups[2]))
        }
        for groups in extractGroups(#"(?<![\w@])@([A-Za-z0-9_]{1,30})\b"#, from: &text) {
            card.socialProfiles.append(SocialProfile(service: "Twitter", username: groups[1]))
        }

        extractDetected(from: &text, into: &card)

        // What remains is names, titles and companies, separated by commas (we left commas where we cut).
        let segments = text
            .components(separatedBy: CharacterSet(charactersIn: ",;\n|"))
            .map { $0.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "-–—"))) }
            .filter { !$0.isEmpty }
        let leftovers = assignWords(segments, to: &card)
        return .contact(card, leftovers: leftovers)
    }

    // MARK: - Actions

    private static func parseAction(_ text: String) -> QuickEntry? {
        let parts = text.split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2, let action = QuickAction.verbs[parts[0].lowercased()] else { return nil }
        let query = parts[1].trimmingCharacters(in: .whitespaces)
        // "Call Me Maybe Inc 555-1234" is a contact being typed, not a command.
        guard !query.isEmpty, !query.contains("@"), query.filter(\.isNumber).count < 3 else { return nil }
        return .action(action, query: query)
    }

    // MARK: - Pattern extraction

    private static let labelWords: [String: String] = [
        "work": "work", "office": "work", "w": "work",
        "home": "home", "h": "home", "personal": "home",
        "mobile": "mobile", "cell": "mobile", "m": "mobile", "iphone": "iPhone",
        "fax": "work fax", "main": "main", "other": "other", "school": "school",
    ]

    /// Removes every regex match from `text` (replacing with a comma) and returns each match with the label
    /// word that preceded it, if any ("work jane@acme.com").
    private static func extract(_ pattern: String, from text: inout String) -> [(String, String?)] {
        extractGroups(pattern, from: &text, captureLabel: true).map { ($0[0], $0.last.flatMap { $0.hasPrefix("label:") ? String($0.dropFirst(6)) : nil }) }
    }

    private static func extractGroups(_ pattern: String, from text: inout String, captureLabel: Bool = false) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        var results: [[String]] = []
        var ranges: [NSRange] = []
        for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            var groups = (0..<m.numberOfRanges).map { i -> String in
                let r = m.range(at: i)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            }
            var range = m.range
            if captureLabel, let (label, labelRange) = precedingLabel(in: ns, before: m.range.location) {
                groups.append("label:" + label)
                range = NSRange(location: labelRange.location, length: NSMaxRange(m.range) - labelRange.location)
            }
            results.append(groups)
            ranges.append(range)
        }
        text = removing(ranges, from: text)
        return results
    }

    private static func precedingLabel(in ns: NSString, before location: Int) -> (String, NSRange)? {
        let prefix = ns.substring(to: location) as NSString
        guard let regex = try? NSRegularExpression(pattern: #"(?i)\b([a-z]+)\s*:?\s*$"#),
              let m = regex.firstMatch(in: prefix as String, range: NSRange(location: 0, length: prefix.length))
        else { return nil }
        let word = prefix.substring(with: m.range(at: 1)).lowercased()
        guard let label = labelWords[word] else { return nil }
        // A one-letter label ("m 555...") only counts when it is its own word.
        if word.count == 1, m.range.location > 0, !" ,;".contains(Character(prefix.substring(with: NSRange(location: m.range.location - 1, length: 1)))) {
            return nil
        }
        return (label, m.range)
    }

    private static func removing(_ ranges: [NSRange], from text: String) -> String {
        let result = NSMutableString(string: text)
        for r in ranges.sorted(by: { $0.location > $1.location }) {
            result.replaceCharacters(in: r, with: ",")
        }
        return result as String
    }

    private static func defaultEmailLabel(_ email: String) -> String {
        let personal = ["gmail.com", "googlemail.com", "icloud.com", "me.com", "mac.com", "yahoo.com", "hotmail.com",
                        "outlook.com", "live.com", "proton.me", "protonmail.com", "fastmail.com", "aol.com", "mail.ru", "yandex.ru"]
        let domain = email.split(separator: "@").last.map { $0.lowercased() } ?? ""
        return personal.contains(domain) ? "home" : "work"
    }

    private static func serviceName(_ raw: String) -> String {
        switch raw.lowercased() {
        case "twitter", "x": "Twitter"
        case "instagram", "insta", "ig": "Instagram"
        case "linkedin": "LinkedIn"
        case "github", "gh": "GitHub"
        case "facebook", "fb": "Facebook"
        case "mastodon": "Mastodon"
        case "threads": "Threads"
        case "telegram", "tg": "Telegram"
        case "bluesky", "bsky": "Bluesky"
        default: raw.capitalized
        }
    }

    // MARK: - Birthday

    private static func extractBirthday(from text: inout String) -> DateComponents? {
        guard let m = text.firstMatch(of: /(?i)\b(?:birthday|bday|b-day|born|dob)\s*:?\s*/) else { return nil }
        // Take the longest run of up to 3 words after the keyword that parses as a date ("Apr 12 1990" before "Apr 12").
        let words = text[m.range.upperBound...].split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
        for n in stride(from: min(3, words.count), through: 1, by: -1) {
            let candidate = words[0..<n].joined(separator: " ")
            guard !candidate.contains(","), let components = parseDate(candidate) else { continue }
            text.replaceSubrange(m.range.lowerBound..<words[n - 1].endIndex, with: ",")
            return components
        }
        return nil
    }

    public static func parseDate(_ raw: String) -> DateComponents? {
        let formats = ["yyyy-MM-dd", "M/d/yyyy", "M/d/yy", "d.M.yyyy", "MMM d yyyy", "MMMM d yyyy", "d MMM yyyy",
                       "d MMMM yyyy", "MMM d", "MMMM d", "d MMM", "d MMMM", "M/d", "d.M"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.isLenient = false
        let cleaned = raw.replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: #"(\d)(st|nd|rd|th)\b"#, with: "$1", options: .regularExpression)
        for format in formats {
            formatter.dateFormat = format
            guard let date = formatter.date(from: cleaned) else { continue }
            let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
            return DateComponents(year: format.contains("y") ? c.year : nil, month: c.month, day: c.day)
        }
        return nil
    }

    // MARK: - Data detectors (phones, links, addresses)

    private static func extractDetected(from text: inout String, into card: inout ContactCard) {
        let types: NSTextCheckingResult.CheckingType = [.phoneNumber, .link, .address]
        guard let detector = try? NSDataDetector(types: types.rawValue) else { return }
        let ns = text as NSString
        var ranges: [NSRange] = []
        for m in detector.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            var range = m.range
            switch m.resultType {
            case .phoneNumber:
                guard let number = m.phoneNumber, number.filter(\.isNumber).count >= 5 else { continue }
                var label = "mobile"
                if let (l, labelRange) = precedingLabel(in: ns, before: m.range.location) {
                    label = l
                    range = NSRange(location: labelRange.location, length: NSMaxRange(m.range) - labelRange.location)
                }
                card.phones.append(LabeledValue(label: label, value: number))
            case .link:
                guard let url = m.url, url.scheme != "mailto" else { continue }
                card.urls.append(LabeledValue(label: "homepage", value: ns.substring(with: m.range)))
            case .address:
                let parts = m.addressComponents ?? [:]
                card.addresses.append(PostalAddress(
                    label: "work",
                    street: parts[.street] ?? "", city: parts[.city] ?? "", state: parts[.state] ?? "",
                    postalCode: parts[.zip] ?? "", country: parts[.country] ?? ""))
            default:
                continue
            }
            ranges.append(range)
        }
        text = removing(ranges, from: text)
    }

    // MARK: - Names, titles, companies

    private static let titleWords: Set<String> = [
        "ceo", "cto", "cfo", "coo", "cmo", "cio", "cpo", "ciso", "vp", "svp", "evp", "president", "founder", "cofounder",
        "co-founder", "director", "manager", "engineer", "developer", "designer", "architect", "consultant", "partner",
        "owner", "head", "lead", "principal", "analyst", "officer", "chief", "recruiter", "attorney", "lawyer",
        "professor", "accountant", "advisor", "adviser", "associate", "assistant", "coordinator", "specialist",
        "executive", "administrator", "intern", "chairman", "chair", "secretary", "treasurer", "agent", "broker",
        "realtor", "editor", "writer", "producer", "scientist", "researcher", "physician", "nurse", "dentist",
        "teacher", "sales", "marketing", "product", "account", "senior", "sr", "jr.", "staff", "md", "gm",
    ]

    private static let orgSuffixes: Set<String> = [
        "inc", "inc.", "llc", "l.l.c.", "ltd", "ltd.", "corp", "corp.", "corporation", "co", "co.", "company", "gmbh",
        "ag", "sa", "s.a.", "plc", "pty", "pty.", "limited", "group", "labs", "lab", "studio", "studios", "bank",
        "university", "llp", "lp", "bv", "b.v.", "srl", "oy", "kk", "holdings", "partners", "agency",
        "systems", "technologies", "solutions", "consulting", "ventures", "capital", "foundation", "institute",
    ]

    private static let nameParticles: Set<String> = ["van", "von", "de", "da", "del", "della", "di", "du", "le", "la", "bin", "al", "ter", "ten", "der", "den", "dos", "das"]
    private static let honorifics: Set<String> = ["mr", "mr.", "mrs", "mrs.", "ms", "ms.", "dr", "dr.", "prof", "prof.", "sir"]

    private static func isTitleWord(_ w: String) -> Bool { titleWords.contains(w.lowercased()) }
    private static func isOrgSuffix(_ w: String) -> Bool { orgSuffixes.contains(w.lowercased()) }

    private static func assignWords(_ segments: [String], to card: inout ContactCard) -> [String] {
        var segments = segments
        var leftovers: [String] = []
        guard !segments.isEmpty else { return [] }

        // The first segment starts with the name; anything after the name words becomes its own segment.
        var words = segments.removeFirst().split(separator: " ").map(String.init)
        while let first = words.first, honorifics.contains(first.lowercased()) { words.removeFirst() }
        let looksLikeCompanyOnly = words.contains(where: isOrgSuffix) && !words.contains(where: isTitleWord)
            && words.count <= 4 && card.emails.allSatisfy({ defaultEmailLabel($0.value) == "work" })
            && segments.isEmpty && words.first.map({ !isPlausibleGivenName($0) }) == true
        if looksLikeCompanyOnly {
            card.organization = words.joined(separator: " ")
            return []
        }

        var nameWords: [String] = []
        while let w = words.first, !isTitleWord(w), !isOrgSuffix(w), w.lowercased() != "at", w.lowercased() != "from" {
            // Stop after a plausible full name unless the next word is a particle or the current one is an initial.
            if nameWords.count >= 2, !nameParticles.contains(nameWords.last!.lowercased()),
               !(nameWords.count == 2 && isInitial(nameWords[1])) {
                break
            }
            nameWords.append(words.removeFirst())
        }
        // "Jane Doe Acme Inc": "Acme" was taken as part of the name only if it preceded a suffix — give it back.
        if let w = words.first, isOrgSuffix(w), nameWords.count > 2 {
            words.insert(nameWords.removeLast(), at: 0)
        }
        applyName(nameWords, to: &card)
        if !words.isEmpty { segments.insert(words.joined(separator: " "), at: 0) }

        for segment in segments {
            // "CEO at Acme", "at Acme", "from Acme"
            if let m = segment.firstMatch(of: /(?i)^(.*?)\s*\b(?:at|from)\s+(.+)$/) {
                setOnce(&card.jobTitle, String(m.1).trimmingCharacters(in: .whitespaces), else: &leftovers)
                setOnce(&card.organization, String(m.2), else: &leftovers)
                continue
            }
            let segWords = segment.split(separator: " ").map(String.init)
            // "Acme Corp CEO": split trailing/leading title words from the company.
            if segWords.contains(where: isOrgSuffix), segWords.contains(where: isTitleWord) {
                if let suffixIndex = segWords.lastIndex(where: isOrgSuffix) {
                    let org = segWords[...suffixIndex]
                    let rest = segWords[(suffixIndex + 1)...]
                    setOnce(&card.organization, org.joined(separator: " "), else: &leftovers)
                    if !rest.isEmpty { setOnce(&card.jobTitle, rest.joined(separator: " "), else: &leftovers) }
                    continue
                }
            }
            if segWords.contains(where: isOrgSuffix) {
                setOnce(&card.organization, segment, else: &leftovers)
            } else if segWords.contains(where: isTitleWord) {
                setOnce(&card.jobTitle, segment, else: &leftovers)
            } else if card.organization.isEmpty {
                card.organization = segment
            } else if card.jobTitle.isEmpty {
                card.jobTitle = segment
            } else {
                leftovers.append(segment)
            }
        }
        return leftovers
    }

    private static func setOnce(_ field: inout String, _ value: String, else leftovers: inout [String]) {
        guard !value.isEmpty else { return }
        if field.isEmpty { field = value } else { leftovers.append(value) }
    }

    private static func isInitial(_ w: String) -> Bool {
        let stem = w.hasSuffix(".") ? w.dropLast() : Substring(w)
        return stem.count == 1 && stem.first!.isLetter
    }

    private static func isPlausibleGivenName(_ w: String) -> Bool {
        Normalize.canonicalGivenName(w.lowercased()) != w.lowercased()
    }

    private static func applyName(_ words: [String], to card: inout ContactCard) {
        let words = words.map(capitalizeIfLowercase)
        switch words.count {
        case 0: break
        case 1: card.givenName = words[0]
        case 2:
            card.givenName = words[0]
            card.familyName = words[1]
        default:
            card.givenName = words[0]
            if let particle = words.dropFirst().firstIndex(where: { nameParticles.contains($0.lowercased()) }) {
                card.middleName = words[1..<particle].joined(separator: " ")
                card.familyName = words[particle...].joined(separator: " ")
            } else {
                card.middleName = words[1..<(words.count - 1)].joined(separator: " ")
                card.familyName = words[words.count - 1]
            }
        }
    }

    /// People type fast: "jane doe" → "Jane Doe", but "McDonald" or "de" is left alone.
    private static func capitalizeIfLowercase(_ w: String) -> String {
        guard w == w.lowercased(), !nameParticles.contains(w) else { return w }
        return w.prefix(1).uppercased() + w.dropFirst()
    }
}
