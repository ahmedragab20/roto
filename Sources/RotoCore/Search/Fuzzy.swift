import Foundation

/// Search for the emoji and clipboard panels.
///
/// A query splits on whitespace into tokens and every token must match some
/// field (order does not matter: "heart red" finds "red heart"). Matching folds
/// case, diacritics and width. Each token takes its best tier: whole field,
/// field prefix, whole word, word prefix, inside a word, word initials, a tight
/// subsequence from a word start, then a one-edit typo at a word start.
/// Typos need 5+ characters, so "cry" can never match "grinning face".
public enum Fuzzy {
    public static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// Single-field score. Higher is better; `nil` means no match.
    public static func score(query: String, in text: String, typos: Bool = true) -> Int? {
        bestScore(query: query, in: [text], typos: typos)
    }

    /// Best score of `query` against several equally weighted fields.
    public static func bestScore(query: String, in texts: [String], typos: Bool = true) -> Int? {
        let prepared = SearchQuery(query)
        if prepared.isEmpty { return 0 }
        return score(prepared, fields: texts.map { SearchField($0, fuzzy: typos) }).map { Int($0.rounded()) }
    }

    /// Items that match, best first. Ties keep the input order.
    public static func ranked<T>(_ items: [T], query: String, keys: (T) -> [String]) -> [T] {
        let prepared = SearchQuery(query)
        if prepared.isEmpty { return items }
        return items.enumerated()
            .compactMap { offset, item -> (Int, Int, T)? in
                let fields = keys(item).map { SearchField($0) }
                guard let score = score(prepared, fields: fields) else { return nil }
                return (rankKey(score), offset, item)
            }
            .sorted { $0.0 != $1.0 ? $0.0 > $1.0 : $0.1 < $1.1 }
            .map(\.2)
    }

    /// Scores a prepared query against prepared fields. `nil` when any token misses.
    /// Roughly 0–125: 100 is a whole-field match, 80–90 whole words, under 60 fuzzy.
    public static func score(_ query: SearchQuery, fields: [SearchField]) -> Double? {
        guard !query.isEmpty else { return 0 }
        var total = 0.0
        for token in query.tokens {
            var best = 0.0
            for field in fields where token.count >= field.minimumTokenLength {
                if let tier = exactTier(token, field.units) {
                    let coverage = 10 * Double(token.count) / Double(max(field.units.count, token.count))
                    best = max(best, (tier + coverage) * field.weight)
                }
            }
            if best == 0 {
                for field in fields where field.fuzzy && token.count >= field.minimumTokenLength {
                    if let tier = fuzzyTier(token, field.units) {
                        best = max(best, tier * field.weight)
                    }
                }
            }
            guard best > 0 else { return nil }
            total += best
        }
        var result = total / Double(query.tokens.count)
        // Only primary fields (a name, the copied text) earn phrase bonuses; a
        // keyword that happens to equal the query should not outrank the name.
        let primary = fields.filter(\.isPrimary)
        if query.tokens.count > 1,
           let field = primary.first(where: { find(query.phrase, in: $0.units, from: 0) != nil }) {
            result += 8 * field.weight
        }
        if let field = primary.first(where: { $0.units == query.phrase }) {
            result += 12 * field.weight
        }
        return result
    }

    /// Sort key that treats scores within 0.05 as equal, so input order breaks ties.
    public static func rankKey(_ score: Double) -> Int {
        Int((score * 20).rounded())
    }

    // MARK: - Tiers

    /// Fuzzy tiers only look at this many UTF-16 units of a field.
    static let fuzzyWindow = 2_000

    private static func exactTier(_ token: [UInt16], _ text: [UInt16]) -> Double? {
        let n = token.count
        let m = text.count
        guard n > 0, n <= m else { return nil }
        var best = 0.0
        var from = 0
        while let pos = find(token, in: text, from: from) {
            let startsWord = pos == 0 || !isWordUnit(text[pos - 1])
            let endsWord = pos + n == m || !isWordUnit(text[pos + n])
            let tier: Double
            if pos == 0 {
                if n == m { return 100 }
                tier = endsWord ? 90 : 84
            } else if startsWord {
                tier = endsWord ? 88 : 80
            } else {
                // One character inside a word is noise ("x" in "box").
                tier = n >= 2 ? 58 : 0
            }
            best = max(best, tier)
            if best >= 90 { break }
            from = pos + 1
        }
        return best > 0 ? best : nil
    }

    private static func fuzzyTier(_ token: [UInt16], _ text: [UInt16]) -> Double? {
        let n = token.count
        guard n >= 2, !text.isEmpty else { return nil }
        let end = min(text.count, fuzzyWindow)
        if let tier = initialsTier(token, text) { return tier }
        if n >= 3, let tier = subsequenceTier(token, text, end: end) { return tier }
        if n >= 5, let distance = typoDistance(token, text, end: end) {
            return 30 - Double(distance - 1) * 4
        }
        return nil
    }

    /// "rh" → "red heart". Short fields only; long text would match everything.
    private static func initialsTier(_ token: [UInt16], _ text: [UInt16]) -> Double? {
        guard text.count <= 80 else { return nil }
        var initials: [UInt16] = []
        for index in text.indices where isWordStart(text, index) {
            initials.append(text[index])
        }
        guard initials.count >= token.count else { return nil }
        for start in 0...(initials.count - token.count)
        where initials[start..<(start + token.count)].elementsEqual(token) {
            return start == 0 ? 54 : 48
        }
        return nil
    }

    /// "thmbs" → "thumbs": every character in order, from a word start, in a tight span.
    private static func subsequenceTier(_ token: [UInt16], _ text: [UInt16], end: Int) -> Double? {
        let n = token.count
        let allowed = n + max(1, n / 3)
        var best: Double?
        for start in 0..<end where text[start] == token[0] && isWordStart(text, start) {
            let limit = min(end, start + allowed)
            var matched = 1
            var last = start
            var run = 1
            var longestRun = 1
            var pos = start + 1
            while matched < n && pos < limit {
                if text[pos] == token[matched] {
                    run = pos == last + 1 ? run + 1 : 1
                    longestRun = max(longestRun, run)
                    last = pos
                    matched += 1
                }
                pos += 1
            }
            guard matched == n, longestRun >= 2 else { continue }
            let span = last - start + 1
            let tier = 40 + Double(min(longestRun, 8)) - Double(span - n) * 2
            best = max(best ?? 0, tier)
        }
        return best
    }

    /// Smallest edit distance (with transpositions) between `token` and a prefix of
    /// some word, within 1 edit for 5–8 characters and 2 edits for longer tokens.
    private static func typoDistance(_ token: [UInt16], _ text: [UInt16], end: Int) -> Int? {
        let n = token.count
        let k = n >= 9 ? 2 : 1
        let width = n + k + 1
        var twoBack = [Int](repeating: 0, count: width)
        var previous = [Int](repeating: 0, count: width)
        var current = [Int](repeating: 0, count: width)
        var best: Int?

        for start in 0..<end where isWordStart(text, start) {
            let maxLength = min(n + k, end - start)
            guard maxLength >= n - k else { continue }
            for j in 0...maxLength { previous[j] = j }
            var abandoned = false
            for i in 1...n {
                current[0] = i
                var rowMin = i
                if maxLength > 0 {
                    for j in 1...maxLength {
                        let cost = token[i - 1] == text[start + j - 1] ? 0 : 1
                        var value = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
                        if i > 1, j > 1,
                           token[i - 1] == text[start + j - 2],
                           token[i - 2] == text[start + j - 1] {
                            value = min(value, twoBack[j - 2] + 1)
                        }
                        current[j] = value
                        rowMin = min(rowMin, value)
                    }
                }
                if rowMin > k {
                    abandoned = true
                    break
                }
                swap(&twoBack, &previous)
                swap(&previous, &current)
            }
            guard !abandoned else { continue }
            for j in max(0, n - k)...maxLength where previous[j] <= k {
                best = min(best ?? k, previous[j])
            }
            if best == 1 { return 1 }
        }
        return best
    }

    // MARK: - Units

    static func find(_ needle: [UInt16], in haystack: [UInt16], from: Int) -> Int? {
        let n = needle.count
        guard n > 0 else { return nil }
        let last = haystack.count - n
        guard from <= last else { return nil }
        let first = needle[0]
        var i = from
        while i <= last {
            if haystack[i] == first {
                var j = 1
                while j < n && haystack[i + j] == needle[j] { j += 1 }
                if j == n { return i }
            }
            i += 1
        }
        return nil
    }

    private static func isWordStart(_ text: [UInt16], _ index: Int) -> Bool {
        isWordUnit(text[index]) && (index == 0 || !isWordUnit(text[index - 1]))
    }

    static func isWordUnit(_ unit: UInt16) -> Bool {
        if unit < 0x80 {
            return (unit >= 0x30 && unit <= 0x39) || (unit >= 0x61 && unit <= 0x7A) || (unit >= 0x41 && unit <= 0x5A)
        }
        // Surrogate halves belong to emoji and other astral characters.
        guard let scalar = Unicode.Scalar(unit) else { return true }
        return scalar.properties.isAlphabetic || scalar.properties.numericType != nil
    }
}

/// A query folded once and split into tokens.
public struct SearchQuery: Sendable, Equatable {
    public let tokens: [[UInt16]]
    public let phrase: [UInt16]

    public var isEmpty: Bool { tokens.isEmpty }

    public init(_ raw: String) {
        let parts = Fuzzy.normalize(raw).split(whereSeparator: \.isWhitespace)
        tokens = parts.map { Array($0.utf16) }
        phrase = Array(parts.joined(separator: " ").utf16)
    }
}

/// A searchable string folded once, with how much a match in it is worth.
public struct SearchField: Sendable, Equatable {
    /// Longest text indexed per field; clipboard entries can be megabytes.
    public static let characterLimit = 32_000

    public let units: [UInt16]
    public let weight: Double
    public let fuzzy: Bool
    public let minimumTokenLength: Int
    public let isPrimary: Bool

    public init(
        _ text: String,
        weight: Double = 1,
        fuzzy: Bool = true,
        minimumTokenLength: Int = 1,
        isPrimary: Bool = true
    ) {
        let clipped = text.utf8.count > Self.characterLimit ? String(text.prefix(Self.characterLimit)) : text
        units = Array(Fuzzy.normalize(clipped).utf16)
        self.weight = weight
        self.fuzzy = fuzzy
        self.minimumTokenLength = minimumTokenLength
        self.isPrimary = isPrimary
    }
}
