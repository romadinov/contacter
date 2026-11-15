import Foundation

public enum MatchConfidence: Int, Comparable, Sendable, Codable, CaseIterable {
    case low, medium, high

    public init(score: Int) {
        switch score {
        case 80...: self = .high
        case 60..<80: self = .medium
        default: self = .low
        }
    }

    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    public var title: String {
        switch self {
        case .high: "High"
        case .medium: "Medium"
        case .low: "Possible"
        }
    }
}

/// An unordered pair of contact ids, used to remember "these are not duplicates" decisions.
public struct ContactPair: Hashable, Sendable, Codable {
    public let first: String
    public let second: String

    public init(_ a: String, _ b: String) {
        (first, second) = a < b ? (a, b) : (b, a)
    }
}

/// What two contacts were found to have in common.
public enum MatchSignal: String, Hashable, Sendable, Codable {
    case email, phone, social, name, company, birthday

    /// Signals that identify a person on their own, as opposed to a name that many people may share.
    public var isIdentifier: Bool { self == .email || self == .phone || self == .social }
}

public struct PairMatch: Hashable, Sendable {
    public let pair: ContactPair
    public let score: Int
    public let reasons: [String]
    public var signals: Set<MatchSignal> = []
    /// True when both contacts carry clearly different person names.
    public var nameConflict = false
    public var confidence: MatchConfidence { MatchConfidence(score: score) }
}

public struct DuplicateGroup: Identifiable, Hashable, Sendable {
    /// Member ids, sorted — stable for as long as the membership is unchanged.
    public let memberIDs: [String]
    public let matches: [PairMatch]
    public var id: String { memberIDs.joined(separator: "|") }

    /// Weakest link in the group: a chain A≈B≈C is only as strong as its weakest edge.
    public var score: Int { matches.map(\.score).min() ?? 0 }
    public var confidence: MatchConfidence { MatchConfidence(score: score) }

    public var reasons: [String] {
        var seen = Set<String>()
        return matches.flatMap(\.reasons).filter { seen.insert($0).inserted }
    }
}

/// Pairwise scoring of two contacts.
public enum DuplicateScorer {
    /// Minimum pair score to be reported as a duplicate at all.
    public static let threshold = 40

    public static func score(_ a: ContactCard, _ b: ContactCard) -> PairMatch {
        var score = 0
        var reasons: [String] = []
        var signals: Set<MatchSignal> = []

        let emailsA = Dictionary(a.emails.compactMap { e in Normalize.email(e.value).map { ($0, e.value) } },
                                 uniquingKeysWith: { x, _ in x })
        let sharedEmails = Set(b.emails.compactMap { Normalize.email($0.value) }).intersection(emailsA.keys)
        if let first = sharedEmails.sorted().first {
            score += 60 + 5 * (sharedEmails.count - 1)
            signals.insert(.email)
            reasons.append("Same email \(emailsA[first] ?? first)")
        }

        let phonesA = Dictionary(a.phones.compactMap { p in Normalize.phone(p.value).map { ($0, p.value) } },
                                 uniquingKeysWith: { x, _ in x })
        let sharedPhones = Set(b.phones.compactMap { Normalize.phone($0.value) }).intersection(phonesA.keys)
        if let first = sharedPhones.sorted().first {
            score += 45 + 5 * (sharedPhones.count - 1)
            signals.insert(.phone)
            reasons.append("Same phone \(phonesA[first] ?? first)")
        }

        let sharedSocial = Set(a.socialProfiles.map(Normalize.social)).intersection(b.socialProfiles.map(Normalize.social))
        if !sharedSocial.isEmpty {
            score += 40
            signals.insert(.social)
            reasons.append("Same social profile")
        }

        let name = NameComparison.compare(a, b)
        if name.isPositive { signals.insert(.name) }
        switch name {
        case .exact(let tokens):
            score += tokens >= 2 ? 40 : 20
            reasons.append("Same name")
        case .nickname:
            score += 35
            reasons.append("Same name (nickname)")
        case .initial:
            score += 35
            reasons.append("Matching initial and surname")
        case .similar:
            score += 30
            reasons.append("Similar name")
        case .conflict:
            score -= 40
        case .unknown:
            break
        }

        let orgA = Normalize.organization(a.organization), orgB = Normalize.organization(b.organization)
        if !orgA.isEmpty, orgA == orgB, name.isPositive || a.isCompany {
            score += 10
            signals.insert(.company)
            reasons.append("Same company")
        }

        if let ba = a.birthday, let bb = b.birthday, ba.month != nil, ba.day != nil {
            if ba.month == bb.month && ba.day == bb.day {
                score += 15
                signals.insert(.birthday)
            reasons.append("Same birthday")
            } else {
                score -= 50
            }
        }

        return PairMatch(pair: ContactPair(a.id, b.id), score: min(score, 100), reasons: reasons,
                         signals: signals, nameConflict: name == .conflict)
    }
}

enum NameComparison: Equatable {
    case exact(tokens: Int), nickname, initial, similar, conflict, unknown

    var isPositive: Bool {
        switch self {
        case .exact, .nickname, .initial, .similar: true
        case .conflict, .unknown: false
        }
    }

    static func compare(_ a: ContactCard, _ b: ContactCard) -> NameComparison {
        // Company cards compare by organization name.
        let fullA = a.isCompany ? Normalize.organization(a.organization) : Normalize.text(a.personName)
        let fullB = b.isCompany ? Normalize.organization(b.organization) : Normalize.text(b.personName)
        guard !fullA.isEmpty, !fullB.isEmpty else { return .unknown }
        if a.isCompany != b.isCompany { return .unknown }

        let tokensA = fullA.split(separator: " ").map(String.init)
        let tokensB = fullB.split(separator: " ").map(String.init)
        if tokensA.sorted() == tokensB.sorted() { return .exact(tokens: tokensA.count) }
        if a.isCompany {
            return StringSimilarity.jaroWinkler(fullA, fullB) >= 0.93 ? .similar : .unknown
        }

        let givenA = Normalize.tokens(a.givenName).first ?? "", givenB = Normalize.tokens(b.givenName).first ?? ""
        let familyA = Normalize.text(a.familyName), familyB = Normalize.text(b.familyName)

        if !familyA.isEmpty, familyA == familyB, !givenA.isEmpty, !givenB.isEmpty {
            if givenA == givenB { return .exact(tokens: 2) }  // middle names differ
            if Normalize.canonicalGivenName(givenA) == Normalize.canonicalGivenName(givenB) { return .nickname }
            if (givenA.count == 1 && givenB.hasPrefix(givenA)) || (givenB.count == 1 && givenA.hasPrefix(givenB)) {
                return .initial
            }
        }

        let sortedA = tokensA.sorted().joined(separator: " "), sortedB = tokensB.sorted().joined(separator: " ")
        let similarity = max(StringSimilarity.jaroWinkler(fullA, fullB), StringSimilarity.jaroWinkler(sortedA, sortedB))
        if similarity >= 0.92, tokensA.count > 1 || tokensB.count > 1 { return .similar }

        // Both names fully specified and clearly different people (e.g. two members of a household).
        if !givenA.isEmpty, !givenB.isEmpty, !familyA.isEmpty, !familyB.isEmpty,
           StringSimilarity.jaroWinkler(givenA, givenB) < 0.8,
           Normalize.canonicalGivenName(givenA) != Normalize.canonicalGivenName(givenB) {
            return .conflict
        }
        if !givenA.isEmpty, !givenB.isEmpty, !familyA.isEmpty, !familyB.isEmpty,
           StringSimilarity.jaroWinkler(familyA, familyB) < 0.8,
           !tokensA.contains(familyB), !tokensB.contains(familyA) {
            return .conflict  // e.g. shared office line: same phone, different surnames
        }
        return .unknown
    }
}

/// Blocking index: only contacts sharing at least one key are ever compared, so detection stays
/// near-linear instead of comparing every pair.
public struct DuplicateIndex: Sendable {
    private var buckets: [String: [Int]] = [:]
    public let cards: [ContactCard]
    /// Very common keys (e.g. the given name "john") are capped to keep comparisons bounded.
    private static let maxBucket = 250

    public init(_ cards: [ContactCard]) {
        self.cards = cards
        for (i, card) in cards.enumerated() {
            for key in Self.blockingKeys(card) { buckets[key, default: []].append(i) }
        }
    }

    static func blockingKeys(_ card: ContactCard) -> Set<String> {
        var keys = Set<String>()
        for e in card.emails { if let k = Normalize.email(e.value) { keys.insert("e:" + k) } }
        for p in card.phones { if let k = Normalize.phone(p.value) { keys.insert("p:" + k) } }
        for s in card.socialProfiles { keys.insert("s:" + Normalize.social(s)) }
        let nameTokens = card.isCompany
            ? Normalize.organization(card.organization).split(separator: " ").map(String.init)
            : Normalize.tokens(card.personName)
        for token in nameTokens where token.count >= 2 {
            keys.insert("t:" + Normalize.canonicalGivenName(token))
            keys.insert("q:" + String(token.prefix(3)))  // catches typos past the 3rd letter
        }
        return keys
    }

    /// Indices of cards that share a blocking key with `card`.
    func candidateIndices(for card: ContactCard) -> Set<Int> {
        var out = Set<Int>()
        for key in Self.blockingKeys(card) {
            guard let bucket = buckets[key] else { continue }
            // A huge prefix bucket ("joh") adds nothing but cost; the exact-token buckets still apply.
            if bucket.count > Self.maxBucket && key.hasPrefix("q:") { continue }
            out.formUnion(bucket.prefix(Self.maxBucket))
        }
        return out
    }

    /// Existing contacts that look like `card` — used to warn before creating a new contact.
    public func matches(for card: ContactCard, ignoring ignored: Set<ContactPair> = []) -> [(card: ContactCard, match: PairMatch)] {
        candidateIndices(for: card)
            .map { cards[$0] }
            .filter { $0.id != card.id && !ignored.contains(ContactPair($0.id, card.id)) }
            .map { ($0, DuplicateScorer.score(card, $0)) }
            .filter { $0.1.score >= DuplicateScorer.threshold }
            .sorted { $0.1.score > $1.1.score }
    }
}

public enum DuplicateFinder {
    public static func findGroups(in cards: [ContactCard], ignoring ignored: Set<ContactPair> = []) -> [DuplicateGroup] {
        let index = DuplicateIndex(cards)
        var parent = Array(cards.indices)
        func find(_ x: Int) -> Int {
            var x = x
            while parent[x] != x {
                parent[x] = parent[parent[x]]
                x = parent[x]
            }
            return x
        }

        var edges: [(Int, Int, PairMatch)] = []
        for i in cards.indices {
            for j in index.candidateIndices(for: cards[i]) where j > i {
                let pair = ContactPair(cards[i].id, cards[j].id)
                guard !ignored.contains(pair) else { continue }
                let match = DuplicateScorer.score(cards[i], cards[j])
                guard match.score >= DuplicateScorer.threshold else { continue }
                edges.append((i, j, match))
                parent[find(i)] = find(j)
            }
        }

        var byRoot: [Int: (members: Set<Int>, matches: [PairMatch])] = [:]
        for (i, j, match) in edges {
            let root = find(i)
            byRoot[root, default: ([], [])].members.formUnion([i, j])
            byRoot[root]!.matches.append(match)
        }
        return byRoot.values
            .map { DuplicateGroup(memberIDs: $0.members.map { cards[$0].id }.sorted(), matches: $0.matches) }
            .sorted { ($0.score, $0.id) > ($1.score, $1.id) }
    }
}
