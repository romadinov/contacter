import Foundation

/// Decides which duplicate groups are safe to merge without a person reviewing them.
///
/// The review list is deliberately generous (it shows "possible" matches); auto-merge is not. A group qualifies
/// only when *every pair* in it — not just a chain A≈B≈C — clears the bar, so one weak link can't drag an
/// unrelated contact into a merge.
public struct AutoMergePolicy: Codable, Hashable, Sendable {
    public enum Strictness: String, Codable, CaseIterable, Sendable {
        /// Score ≥ 90: typically a shared identifier plus a matching name.
        case strict
        /// Score ≥ 80: the "High" confidence band.
        case standard

        public var minimumScore: Int {
            switch self {
            case .strict: 90
            case .standard: 80
            }
        }

        public var title: String {
            switch self {
            case .strict: "Strict"
            case .standard: "Standard"
            }
        }
    }

    public var strictness: Strictness = .strict
    /// Require each pair to share an email, phone number or social profile; a matching name alone is never enough.
    public var requireSharedIdentifier = true
    /// Larger clusters are more often a shared office line or mailbox than one person; leave them for review.
    public var maxGroupSize = 3

    public init(strictness: Strictness = .strict, requireSharedIdentifier: Bool = true, maxGroupSize: Int = 3) {
        self.strictness = strictness
        self.requireSharedIdentifier = requireSharedIdentifier
        self.maxGroupSize = maxGroupSize
    }

    public enum Verdict: Equatable, Sendable {
        case eligible
        case tooLarge
        case weakPair(String, String)
        case noSharedIdentifier(String, String)
        case nameConflict(String, String)
        case missingContact
    }

    public func verdict(for group: DuplicateGroup, cards: [String: ContactCard]) -> Verdict {
        guard group.memberIDs.count <= maxGroupSize else { return .tooLarge }
        let members = group.memberIDs.compactMap { cards[$0] }
        guard members.count == group.memberIDs.count, members.count > 1 else { return .missingContact }

        for (i, a) in members.enumerated() {
            for b in members[(i + 1)...] {
                let match = DuplicateScorer.score(a, b)
                if match.nameConflict { return .nameConflict(a.id, b.id) }
                if requireSharedIdentifier, !match.signals.contains(where: \.isIdentifier) {
                    return .noSharedIdentifier(a.id, b.id)
                }
                if match.score < strictness.minimumScore { return .weakPair(a.id, b.id) }
            }
        }
        return .eligible
    }

    public func isEligible(_ group: DuplicateGroup, cards: [String: ContactCard]) -> Bool {
        verdict(for: group, cards: cards) == .eligible
    }
}
