import Foundation

/// Glyphs and names we never offer in the picker.
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
    ]

    private static let bannedEmoji: Set<String> = [
        "🇮🇱", "✡️", "🕎", "🕍", "🔯", "✝️", "☦️", "⛪", "💒", "🛐",
        "🎄", "🎅", "🤶", "🧑‍🎄",
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
