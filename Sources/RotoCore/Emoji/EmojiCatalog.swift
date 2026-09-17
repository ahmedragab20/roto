import Foundation

public struct EmojiEntry: Sendable, Equatable, Codable, Identifiable {
    public var emoji: String
    public var name: String
    public var group: String
    public var keywords: [String]
    public var skinTones: [String: String]?

    public var id: String { emoji }

    public init(
        emoji: String,
        name: String,
        group: String,
        keywords: [String] = [],
        skinTones: [String: String]? = nil
    ) {
        self.emoji = emoji
        self.name = name
        self.group = group
        self.keywords = keywords
        self.skinTones = skinTones
    }

    public func glyph(skinTone: String) -> String {
        if skinTone == "default" { return emoji }
        return skinTones?[skinTone] ?? emoji
    }
}

public struct EmojiSection: Sendable, Equatable, Identifiable {
    public var title: String
    public var entries: [EmojiEntry]
    public var id: String { title }

    public init(title: String, entries: [EmojiEntry]) {
        self.title = title
        self.entries = entries
    }
}

public final class EmojiCatalog: @unchecked Sendable {
    public private(set) var entries: [EmojiEntry]
    public private(set) var recents: [String]
    public var skinTone: String
    private let lock = NSLock()
    private var searchFields: [[SearchField]]?
    public static let recentLimit = 24
    public static let recentsTitle = "Recently Used"

    public init(entries: [EmojiEntry], recents: [String] = [], skinTone: String = "default") {
        self.entries = entries.filter { !EmojiPolicy.isExcluded($0) }
        self.recents = recents
        self.skinTone = skinTone
    }

    /// Drop glyphs the current OS cannot draw (LastResort tofu).
    public func filterGlyphs(_ keep: (String) -> Bool) {
        lock.lock()
        defer { lock.unlock() }
        entries = entries.compactMap { entry in
            guard keep(entry.emoji) else { return nil }
            var copy = entry
            if let tones = entry.skinTones {
                let kept = tones.filter { keep($0.value) }
                copy.skinTones = kept.isEmpty ? nil : kept
            }
            return copy
        }
        searchFields = nil
    }

    public static func load(from data: Data, recents: [String] = [], skinTone: String = "default") throws -> EmojiCatalog {
        let entries = try JSONDecoder().decode([EmojiEntry].self, from: data)
        return EmojiCatalog(entries: entries, recents: recents, skinTone: skinTone)
    }

    /// Builds the search index now instead of on the first keystroke.
    public func prepareSearch() {
        _ = snapshotForSearch()
    }

    /// Best match first; equal scores keep catalog order.
    public func filtered(_ query: String) -> [EmojiEntry] {
        let prepared = SearchQuery(query)
        if prepared.isEmpty {
            lock.lock()
            defer { lock.unlock() }
            return entries
        }
        let (snapshot, fields) = snapshotForSearch()
        lock.lock()
        let recent = Set(recents)
        lock.unlock()
        return snapshot.indices
            .compactMap { index -> (score: Int, index: Int)? in
                guard var score = Fuzzy.score(prepared, fields: fields[index]) else { return nil }
                let entry = snapshot[index]
                if let rank = Self.commonRank[entry.emoji] {
                    score += 6 * (1 - Double(rank) / Double(Self.common.count))
                }
                if recent.contains(entry.emoji) {
                    score += 3
                }
                return (Fuzzy.rankKey(score), index)
            }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }
            .map { snapshot[$0.index] }
    }

    /// Recents first, then every group in catalog order.
    public func browseSections() -> [EmojiSection] {
        let recent = recentEntries()
        lock.lock()
        let snapshot = entries
        lock.unlock()

        var groups: [EmojiSection] = []
        for entry in snapshot {
            if groups.last?.title == entry.group {
                groups[groups.count - 1].entries.append(entry)
            } else {
                groups.append(EmojiSection(title: entry.group, entries: [entry]))
            }
        }
        return recent.isEmpty ? groups : [EmojiSection(title: Self.recentsTitle, entries: recent)] + groups
    }

    private func snapshotForSearch() -> ([EmojiEntry], [[SearchField]]) {
        lock.lock()
        defer { lock.unlock() }
        if let searchFields {
            return (entries, searchFields)
        }
        var groups: [String: SearchField] = [:]
        let built = entries.map { entry -> [SearchField] in
            var fields = [
                SearchField(entry.emoji, fuzzy: false),
                SearchField(entry.name),
            ]
            fields += entry.keywords.map { SearchField($0, weight: 0.9, isPrimary: false) }
            let group = groups[entry.group]
                ?? SearchField(entry.group, weight: 0.3, fuzzy: false, minimumTokenLength: 3, isPrimary: false)
            groups[entry.group] = group
            fields.append(group)
            return fields
        }
        searchFields = built
        return (entries, built)
    }

    public func recordUse(_ emoji: String) {
        lock.lock()
        defer { lock.unlock() }
        recents.removeAll { $0 == emoji }
        recents.insert(emoji, at: 0)
        if recents.count > Self.recentLimit {
            recents = Array(recents.prefix(Self.recentLimit))
        }
    }

    public func recentEntries() -> [EmojiEntry] {
        lock.lock()
        let recent = recents
        let snapshot = entries
        lock.unlock()
        return recent.compactMap { glyph in
            snapshot.first { $0.emoji == glyph || $0.skinTones?.values.contains(glyph) == true }
        }
    }

    public func encodeRecents() throws -> Data {
        lock.lock()
        let recent = recents
        lock.unlock()
        return try JSONEncoder().encode(recent)
    }

    public static func decodeRecents(from data: Data) -> [String] {
        (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    /// Widely used emoji, most used first. A small ranking nudge so "heart"
    /// puts ❤️ ahead of ♥️ and "cry" puts 😭 ahead of 😿.
    static let common: [String] = [
        "😂", "❤️", "🤣", "👍", "😭", "🙏", "😘", "🥰", "😍", "😊", "🎉", "😁", "💕", "🥺", "😅", "🔥",
        "☺️", "🤦", "♥️", "🤷", "🙄", "😆", "🤗", "😉", "🎂", "🤔", "👏", "🙂", "😳", "🥳", "😎", "👌",
        "💜", "😔", "💪", "✨", "💖", "👀", "😋", "😏", "😢", "👉", "💗", "😩", "💯", "🌹", "💞", "🎈",
        "💙", "😃", "😡", "💐", "😜", "🙈", "🤞", "😄", "🤤", "🙌", "🤪", "❣️", "😀", "💋", "💀", "👇",
        "💔", "😌", "💓", "🤩", "🙃", "😬", "😱", "😴", "🤭", "😐", "🌞", "😒", "😇", "🌸", "😈", "🎶",
        "✌️", "🎊", "🥵", "😞", "💚", "☀️", "🖤", "💰", "😚", "👑", "🎁", "💥", "🙋", "☹️", "😑", "🥴",
        "👈", "💩", "✅", "👋",
    ]

    private static let commonRank: [String: Int] = Dictionary(
        common.enumerated().map { ($0.element, $0.offset) },
        uniquingKeysWith: { first, _ in first }
    )

    public static let fallback: [EmojiEntry] = [
        EmojiEntry(emoji: "😀", name: "grinning face", group: "Smileys & Emotion", keywords: ["smile", "happy"]),
        EmojiEntry(emoji: "😂", name: "face with tears of joy", group: "Smileys & Emotion", keywords: ["laugh"]),
        EmojiEntry(emoji: "❤️", name: "red heart", group: "Smileys & Emotion", keywords: ["love", "heart"]),
        EmojiEntry(emoji: "👍", name: "thumbs up", group: "People & Body", keywords: ["yes", "ok"], skinTones: [
            "light": "👍🏻", "medium-light": "👍🏼", "medium": "👍🏽", "medium-dark": "👍🏾", "dark": "👍🏿",
        ]),
        EmojiEntry(emoji: "👋", name: "waving hand", group: "People & Body", keywords: ["wave", "hello"], skinTones: [
            "light": "👋🏻", "medium-light": "👋🏼", "medium": "👋🏽", "medium-dark": "👋🏾", "dark": "👋🏿",
        ]),
        EmojiEntry(emoji: "🔥", name: "fire", group: "Travel & Places", keywords: ["hot"]),
        EmojiEntry(emoji: "✅", name: "check mark button", group: "Symbols", keywords: ["done", "yes"]),
        EmojiEntry(emoji: "✨", name: "sparkles", group: "Activities", keywords: ["star"]),
    ]
}
