import ContacterCore
import SwiftUI

struct AvatarView: View {
    @Environment(ContactStore.self) private var store
    let id: String
    let initials: String
    var size: CGFloat = 28

    var body: some View {
        Group {
            if let image = store.thumbnail(id: id) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Text(initials)
                    .font(.system(size: size * 0.4, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Self.color(for: id).gradient)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
    }

    private static let palette: [Color] = [.blue, .indigo, .purple, .pink, .orange, .teal, .green, .brown, .cyan, .mint]

    /// Deterministic across launches (unlike `hashValue`).
    private static func color(for id: String) -> Color {
        palette[id.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF } % palette.count]
    }
}

struct ContactRow: View {
    let id: String
    let name: String
    let subtitle: String
    let initials: String

    var body: some View {
        HStack(spacing: 10) {
            AvatarView(id: id, initials: initials, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

extension ContactRow {
    init(card: ContactCard) {
        self.init(id: card.id, name: card.displayName, subtitle: card.subtitle, initials: card.initials)
    }
}

struct ConfidenceBadge: View {
    let confidence: MatchConfidence

    var body: some View {
        Text(confidence.title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: .capsule)
    }

    private var color: Color {
        switch confidence {
        case .high: .red
        case .medium: .orange
        case .low: .secondary
        }
    }
}

/// A compact, read-only list of everything on a card. Used for drafts, duplicate members and merge previews.
struct CardFieldsView: View {
    let card: ContactCard

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 4) {
            if !card.nickname.isEmpty { row("nickname", card.nickname) }
            if !card.jobTitle.isEmpty { row("title", card.jobTitle) }
            if !card.organization.isEmpty, !card.isCompany { row("company", card.organization) }
            if !card.department.isEmpty { row("department", card.department) }
            ForEach(card.phones, id: \.self) { row(label($0.label, "phone"), $0.value) }
            ForEach(card.emails, id: \.self) { row(label($0.label, "email"), $0.value) }
            ForEach(card.urls, id: \.self) { row(label($0.label, "url"), $0.value) }
            ForEach(card.socialProfiles, id: \.self) { row($0.service.lowercased(), "@" + $0.username) }
            ForEach(card.addresses, id: \.self) { row(label($0.label, "address"), $0.singleLine) }
            if let birthday = card.birthday { row("birthday", BirthdayFormat.string(birthday)) }
        }
        .font(.callout)
    }

    private func label(_ raw: String?, _ fallback: String) -> String {
        let l = ContactMapping.displayLabel(raw)
        return l.isEmpty ? fallback : l
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            Text(value).textSelection(.enabled).lineLimit(2)
        }
    }
}

enum BirthdayFormat {
    static func string(_ c: DateComponents) -> String {
        guard let month = c.month, let day = c.day,
              let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: c.year ?? 2000, month: month, day: day))
        else { return "" }
        return c.year == nil
            ? date.formatted(.dateTime.month(.wide).day())
            : date.formatted(.dateTime.month(.wide).day().year())
    }
}

extension ContactCard {
    /// Anything beyond a bare name — i.e. the user is clearly typing a new contact rather than searching.
    var hasDetails: Bool {
        !phones.isEmpty || !emails.isEmpty || !urls.isEmpty || !addresses.isEmpty || !socialProfiles.isEmpty
            || birthday != nil || !jobTitle.isEmpty
    }
}
