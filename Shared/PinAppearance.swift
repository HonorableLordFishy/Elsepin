import Foundation

enum HeldLocationSymbol: String, CaseIterable, Identifiable {
    case automatic, location, person, walking, star

    static let preferenceKey = "locus.heldLocationSymbol"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .location: return "Location arrow"
        case .person: return "Person"
        case .walking: return "Walking figure"
        case .star: return "Star"
        }
    }

    func icon(travelMode: TravelMode) -> String {
        switch self {
        case .automatic: return travelMode.icon
        case .location: return "location.fill"
        case .person: return "person.fill"
        case .walking: return "figure.walk"
        case .star: return "star.fill"
        }
    }

    static func stored(in defaults: UserDefaults) -> Self {
        defaults.string(forKey: preferenceKey).flatMap(Self.init(rawValue:)) ?? .automatic
    }
}

enum PinAppearance {
    /// Reject invalid edits before the native text field displays them. Choosing
    /// another emoji replaces the current symbol instead of appending a second.
    static func applyingEmojiEdit(to current: String, range: NSRange, replacement: String) -> String? {
        guard let range = Range(range, in: current) else { return nil }
        if replacement.isEmpty { return range.isEmpty ? current : "" }
        let proposed = current.replacingCharacters(in: range, with: replacement)
        if isSingleEmoji(proposed) { return proposed }
        return isSingleEmoji(replacement) ? replacement : nil
    }

    /// A whole extended grapheme preserves flags, ZWJ families and skin tones.
    /// ASCII digits alone have the emoji property, but aren't emoji glyphs.
    static func isSingleEmoji(_ text: String) -> Bool {
        guard text.count == 1, text.unicodeScalars.count <= 32 else { return false }
        return text.unicodeScalars.contains { $0.properties.isEmojiPresentation } ||
            (text.unicodeScalars.contains { $0.properties.isEmoji } &&
             text.unicodeScalars.contains { $0.value == 0xFE0F || $0.value == 0x20E3 })
    }
}
