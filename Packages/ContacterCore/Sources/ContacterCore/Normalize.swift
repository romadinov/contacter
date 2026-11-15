import Foundation

/// Canonical forms used for searching, comparing and de-duplicating contact data.
public enum Normalize {
    /// Lowercased, diacritic-free, punctuation replaced by single spaces.
    public static func text(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
        var out = ""
        var lastWasSpace = true
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                out.unicodeScalars.append(scalar)
                lastWasSpace = false
            } else if scalar == "'" || scalar == "’" {
                continue  // O'Brien == OBrien
            } else if !lastWasSpace {
                out.append(" ")
                lastWasSpace = true
            }
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    public static func tokens(_ s: String) -> [String] {
        text(s).split(separator: " ").map(String.init)
    }

    /// Lowercased address with sub-addressing ("+tag") removed, and Gmail dots ignored.
    public static func email(_ s: String) -> String? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let at = trimmed.lastIndex(of: "@") else { return nil }
        var local = String(trimmed[..<at])
        var domain = String(trimmed[trimmed.index(after: at)...])
        guard !local.isEmpty, domain.contains(".") else { return nil }
        if let plus = local.firstIndex(of: "+") { local = String(local[..<plus]) }
        if domain == "googlemail.com" { domain = "gmail.com" }
        if domain == "gmail.com" { local = local.replacingOccurrences(of: ".", with: "") }
        return local + "@" + domain
    }

    /// Comparison key for a phone number: its last 9 digits, which survives differing country-code and
    /// trunk-prefix formatting ("+61 412 345 678" == "0412 345 678"). Numbers shorter than 7 digits are ignored.
    public static func phone(_ s: String) -> String? {
        var digits = s.filter(\.isASCIIDigit)
        if let ext = s.range(of: #"(?i)(ext\.?|x|#)\s*\d+$"#, options: .regularExpression) {
            digits = s[..<ext.lowerBound].filter(\.isASCIIDigit)
        }
        guard digits.count >= 7 else { return nil }
        return String(digits.suffix(9))
    }

    /// Company name without legal-form suffixes, so "Apple" == "Apple Inc." == "Apple, Inc".
    public static func organization(_ s: String) -> String {
        tokens(s).filter { !legalForms.contains($0) }.joined(separator: " ")
    }

    private static let legalForms: Set<String> = [
        "inc", "incorporated", "llc", "ltd", "limited", "corp", "corporation", "co", "company", "gmbh", "ag", "plc",
        "pty", "llp", "lp", "bv", "sa", "srl", "oy", "ab", "kk", "the",
    ]

    public static func url(_ s: String) -> String {
        var u = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for prefix in ["https://", "http://"] where u.hasPrefix(prefix) { u.removeFirst(prefix.count) }
        if u.hasPrefix("www.") { u.removeFirst(4) }
        while u.hasSuffix("/") { u.removeLast() }
        return u
    }

    public static func social(_ p: SocialProfile) -> String {
        text(p.service) + ":" + text(p.username.hasPrefix("@") ? String(p.username.dropFirst()) : p.username)
    }

    public static func address(_ a: PostalAddress) -> String {
        text([a.street, a.city, a.postalCode].joined(separator: " "))
    }

    /// Maps a given-name token to a canonical form so "Bob" matches "Robert".
    public static func canonicalGivenName(_ token: String) -> String {
        nicknames[token] ?? token
    }

    private static let nicknames: [String: String] = {
        let groups: [[String]] = [
            ["robert", "rob", "bob", "bobby", "robbie"],
            ["william", "will", "bill", "billy", "liam", "willy"],
            ["james", "jim", "jimmy", "jamie"],
            ["michael", "mike", "mikey", "mick"],
            ["alexander", "alex", "alexey", "alexei", "aleksey", "alexandr", "sasha", "alek"],
            ["alexandra", "alexa", "lexi", "sandra"],
            ["katherine", "catherine", "kathryn", "kate", "katie", "kathy", "cathy", "kat"],
            ["elizabeth", "liz", "lizzie", "beth", "betty", "eliza", "libby"],
            ["thomas", "tom", "tommy"],
            ["david", "dave", "davey"],
            ["daniel", "dan", "danny"],
            ["christopher", "chris", "kit"],
            ["christine", "christina", "tina", "chrissy"],
            ["nicholas", "nick", "nicky", "nico"],
            ["matthew", "matt"],
            ["joseph", "joe", "joey"],
            ["anthony", "tony"],
            ["steven", "stephen", "steve"],
            ["andrew", "andy", "drew"],
            ["benjamin", "ben", "benny"],
            ["samuel", "sam", "sammy"],
            ["samantha", "sammie"],
            ["jennifer", "jen", "jenny", "jenn"],
            ["patrick", "pat", "paddy"],
            ["patricia", "patty", "trish"],
            ["richard", "rick", "ricky", "rich", "dick"],
            ["edward", "ed", "eddie", "ted", "ned"],
            ["gregory", "greg"],
            ["john", "jon", "johnny", "jack"],
            ["susan", "sue", "suzy"],
            ["margaret", "maggie", "meg", "peggy"],
            ["jonathan", "jonny"],
            ["timothy", "tim", "timmy"],
            ["charles", "charlie", "chuck"],
            ["kenneth", "ken", "kenny"],
            ["ronald", "ron", "ronnie"],
            ["donald", "don", "donnie"],
            ["lawrence", "larry"],
            ["jeffrey", "jeff"],
            ["peter", "pete"],
            ["vladimir", "vlad", "volodya"],
            ["dmitry", "dmitri", "dima"],
            ["ekaterina", "katya"],
            ["nikolay", "nikolai", "kolya"],
            ["mikhail", "misha"],
        ]
        var map: [String: String] = [:]
        for group in groups {
            for name in group where map[name] == nil { map[name] = group[0] }
        }
        return map
    }()
}

extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
