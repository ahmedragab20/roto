import Foundation

/// Glyphs and names the picker does not offer.
///
/// The set is curated rather than complete. It carries the symbols, buildings
/// and figures of one faith, Islam, and leaves out those of the others, along
/// with a short list of further glyphs the project chooses not to ship.
///
/// Matching is deliberately narrow — exact glyphs and exact names, with
/// substrings only where the word belongs to no other subject — so that a
/// flower, a bird, a rainbow or a building never disappears alongside them.
/// Keep this list and the copy in `scripts/gen-emoji.swift` in step.
public enum EmojiPolicy {
    private static let bannedNames: Set<String> = [
        "flag: israel",
        "star of david",
        "menorah",
        "synagogue",
        "dotted six-pointed star",
        "latin cross",
        "orthodox cross",
        "church",
        "wedding",
        "place of worship",
        "christmas tree",
        "santa claus",
        "mrs. claus",
        "mx claus",
        "baby angel",
        "hindu temple",
        "om",
        "wheel of dharma",
        "shinto shrine",
        "yin yang",
        "khanda",
        "bikini",
        "transgender flag",
        "transgender symbol",
        "rainbow flag",
    ]

    private static let bannedSubstrings = [
        "israel",
        "star of david",
        "menorah",
        "synagogue",
        "six-pointed star",
        "latin cross",
        "orthodox cross",
        "christian",
        "hanukkah",
        "judaism",
        "jewish",
        "hindu temple",
        "wheel of dharma",
        "dharma",
        "shinto",
        "taoist",
        "yinyang",
        "sikh",
        "khanda",
        "baby angel",
        "bikini",
        "rainbow flag",
    ]

    private static let bannedEmoji: Set<String> = [
        "🇮🇱", "✡️", "🕎", "🕍", "🔯", "✝️", "☦️", "⛪", "💒", "🛐",
        "🎄", "🎅", "🤶", "🧑‍🎄",
        "👼", "🛕", "🕉️", "☸️", "⛩️", "☯️", "🪯",
        "👙", "🏳️\u{200D}⚧️", "⚧️", "🏳️\u{200D}🌈",
    ]

    public static func isExcluded(_ entry: EmojiEntry) -> Bool {
        isExcluded(emoji: entry.emoji, name: entry.name, keywords: entry.keywords)
    }

    public static func isExcluded(emoji: String, name: String, keywords: [String]) -> Bool {
        if bannedEmoji.contains(emoji) { return true }
        let nameKey = name.lowercased()
        if bannedNames.contains(nameKey) { return true }
        let blob = ([name] + keywords).joined(separator: " ").lowercased()
        return bannedSubstrings.contains { blob.contains($0) }
    }
}
