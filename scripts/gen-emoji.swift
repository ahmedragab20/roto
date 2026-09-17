#!/usr/bin/env swift
import Foundation

// Developer-only generator. Not linked into the app. Downloads public Unicode
// and CLDR tables, then writes Sources/Roto/Resources/emoji.json.

let root = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    .deletingLastPathComponent().deletingLastPathComponent()
let outURL = root.appendingPathComponent("Sources/Roto/Resources/emoji.json")

let emojiTestURL = URL(string: "https://unicode.org/Public/emoji/latest/emoji-test.txt")!
let annotationsURL = URL(string: "https://raw.githubusercontent.com/unicode-org/cldr-json/main/cldr-json/cldr-annotations-full/annotations/en/annotations.json")!
// Keywords for sequences (ZWJ, keycaps, flags) live in the derived table.
let derivedAnnotationsURL = URL(string: "https://raw.githubusercontent.com/unicode-org/cldr-json/main/cldr-json/cldr-annotations-derived-full/annotationsDerived/en/annotations.json")!

struct Entry: Codable {
    var emoji: String
    var name: String
    var group: String
    var keywords: [String]
    var skinTones: [String: String]?
}

func fetch(_ url: URL) throws -> Data {
    let sem = DispatchSemaphore(value: 0)
    var result: Result<Data, Error>?
    let task = URLSession.shared.dataTask(with: url) { data, response, error in
        if let error {
            result = .failure(error)
        } else if let data {
            result = .success(data)
        } else {
            result = .failure(NSError(domain: "gen-emoji", code: 1, userInfo: [NSLocalizedDescriptionKey: "empty response from \(url)"]))
        }
        sem.signal()
    }
    task.resume()
    sem.wait()
    return try result!.get()
}

func scalars(from hex: String) -> String? {
    var result = ""
    for part in hex.split(separator: " ") {
        guard let value = UInt32(part, radix: 16), let scalar = Unicode.Scalar(value) else { return nil }
        result.unicodeScalars.append(scalar)
    }
    return result
}

let skinMap: [(String, String)] = [
    ("1F3FB", "light"),
    ("1F3FC", "medium-light"),
    ("1F3FD", "medium"),
    ("1F3FE", "medium-dark"),
    ("1F3FF", "dark"),
]
let skinHex = Set(skinMap.map(\.0))

func stripSkin(_ hex: String) -> (base: String, tone: String?) {
    let parts = hex.split(separator: " ").map(String.init)
    var tone: String?
    var base: [String] = []
    for part in parts {
        if let match = skinMap.first(where: { $0.0 == part }) {
            tone = match.1
        } else {
            base.append(part)
        }
    }
    return (base.joined(separator: " "), tone)
}

print("Fetching emoji-test.txt…")
let testText = String(data: try fetch(emojiTestURL), encoding: .utf8) ?? ""
print("Fetching CLDR annotations…")
var keywords: [String: [String]] = [:]
for (url, rootKey) in [(annotationsURL, "annotations"), (derivedAnnotationsURL, "annotationsDerived")] {
    guard let data = try? fetch(url),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let annotations = json[rootKey] as? [String: Any],
          let table = annotations["annotations"] as? [String: Any]
    else {
        print("warning: no annotations from \(url)")
        continue
    }
    for (emoji, value) in table {
        if let dict = value as? [String: Any], let list = dict["default"] as? [String], keywords[emoji] == nil {
            keywords[emoji] = list
        }
    }
}

/// CLDR keys drop the U+FE0F presentation selector that emoji-test.txt keeps.
func keywordsFor(_ emoji: String) -> [String] {
    if let list = keywords[emoji] { return list }
    var bare = ""
    bare.unicodeScalars.append(contentsOf: emoji.unicodeScalars.filter { $0.value != 0xFE0F })
    return keywords[bare] ?? []
}

var group = "Other"
var byBase: [String: (name: String, group: String, emoji: String, tones: [String: String])] = [:]
var order: [String] = []

for line in testText.split(separator: "\n", omittingEmptySubsequences: false) {
    let raw = String(line)
    if raw.hasPrefix("# group: ") {
        group = String(raw.dropFirst("# group: ".count))
        continue
    }
    if raw.hasPrefix("#") || raw.trimmingCharacters(in: .whitespaces).isEmpty {
        continue
    }
    guard raw.contains("; fully-qualified") else { continue }
    let parts = raw.split(separator: ";", maxSplits: 1)
    guard let hexPart = parts.first else { continue }
    let hex = hexPart.trimmingCharacters(in: .whitespaces)
    guard let emoji = scalars(from: hex) else { continue }
    var name = ""
    if let hash = raw.range(of: "# ") {
        let after = raw[hash.upperBound...]
        // "# 😀 E1.0 grinning face"
        let tokens = after.split(separator: " ", maxSplits: 2)
        if tokens.count >= 3 {
            name = tokens[2].trimmingCharacters(in: .whitespaces)
        }
    }
    let stripped = stripSkin(hex)
    if let tone = stripped.tone {
        if byBase[stripped.base] == nil { continue }
        var current = byBase[stripped.base]!
        current.tones[tone] = emoji
        byBase[stripped.base] = current
        continue
    }
    if byBase[stripped.base] == nil {
        order.append(stripped.base)
        byBase[stripped.base] = (name, group, emoji, [:])
    }
}

func isExcluded(emoji: String, name: String, keywords: [String] = []) -> Bool {
    let bannedEmoji: Set<String> = [
        "🇮🇱", "✡️", "🕎", "🕍", "🔯", "✝️", "☦️", "⛪", "💒", "🛐",
        "🎄", "🎅", "🤶", "🧑‍🎄",
    ]
    let bannedNames: Set<String> = [
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
    let bannedSubstrings = [
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
    if bannedEmoji.contains(emoji) { return true }
    let nameKey = name.lowercased()
    if bannedNames.contains(nameKey) { return true }
    let blob = ([name] + keywords).joined(separator: " ").lowercased()
    return bannedSubstrings.contains { blob.contains($0) }
}

var entries: [Entry] = []
for key in order {
    guard let item = byBase[key] else { continue }
    if isExcluded(emoji: item.emoji, name: item.name) { continue }
    let kws = keywordsFor(item.emoji)
    if isExcluded(emoji: item.emoji, name: item.name, keywords: kws) { continue }
    entries.append(Entry(
        emoji: item.emoji,
        name: item.name,
        group: item.group,
        keywords: kws,
        skinTones: item.tones.isEmpty ? nil : item.tones
    ))
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
let data = try encoder.encode(entries)
try FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try data.write(to: outURL)
print("Wrote \(entries.count) emoji to \(outURL.path)")
