import Foundation
import TOMLKit

public enum KeymapKind: String, CaseIterable, Sendable {
    case window, app, clipboard, emoji, windows, cheatsheet
}

public struct KeymapBinding: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var kind: KeymapKind
    public var shortcut: String
    public var target: String

    public init(id: UUID = UUID(), kind: KeymapKind, shortcut: String, target: String = "") {
        self.id = id
        self.kind = kind
        self.shortcut = shortcut
        self.target = target
    }
}

public enum KeymapEditor {
    /// Keep every existing row, including physical aliases, so users can fix conflicts.
    public static func bindings(in config: Config) -> [KeymapBinding] {
        var result = config.hotkeys.window.keys.sorted().map {
            KeymapBinding(kind: .window, shortcut: $0, target: config.hotkeys.window[$0]!)
        }
        result += config.hotkeys.apps.keys.sorted().map {
            KeymapBinding(kind: .app, shortcut: $0, target: config.hotkeys.apps[$0]!)
        }
        for (kind, shortcut) in popupValues(config.hotkeys) {
            if let shortcut { result.append(KeymapBinding(kind: kind, shortcut: shortcut)) }
        }
        return result
    }

    public static func hotkeys(from bindings: [KeymapBinding], config: Config) throws -> Config.Hotkeys {
        var output = Config.Hotkeys()
        var seen: [String: String] = [:]
        var popups: Set<KeymapKind> = []
        for binding in bindings {
            let combo = try KeyCombo.parse(binding.shortcut)
            let physical = "\(combo.keyCode):\(combo.carbonModifiers)"
            if let prior = seen[physical] {
                throw ConfigError.validation("hotkey '\(combo.canonical)' is bound twice (\(prior) and \(binding.kind.rawValue))")
            }
            seen[physical] = binding.kind.rawValue
            switch binding.kind {
            case .window:
                _ = try Layout.resolveWindowCommand(binding.target, layouts: config.window.layouts)
                output.window[binding.shortcut] = binding.target
            case .app:
                guard !binding.target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ConfigError.validation("app hotkey '\(binding.shortcut)' has an empty app")
                }
                output.apps[binding.shortcut] = binding.target
            case .clipboard, .emoji, .windows, .cheatsheet:
                guard popups.insert(binding.kind).inserted else {
                    throw ConfigError.validation("multiple hotkeys.\(binding.kind.rawValue) popup rows")
                }
                switch binding.kind {
                case .clipboard: output.clipboard = binding.shortcut
                case .emoji: output.emoji = binding.shortcut
                case .windows: output.windows = binding.shortcut
                case .cheatsheet: output.cheatsheet = binding.shortcut
                default: break
                }
            }
        }
        return output
    }

    public static func windowActions(in config: Config) -> [String] {
        let special = ["center", "center-large", "next-display", "prev-display", "focus-left", "focus-right",
                       "focus-up", "focus-down", "focus-next-display", "focus-prev-display"]
        return Array(Set(Layout.presets.keys).union(special).union(config.window.layouts.keys.map { "layout:\($0)" })).sorted()
    }

    public static func updating(_ source: String, bindings: [KeymapBinding]) throws -> String {
        var config = try ConfigLoader.parse(source)
        config.hotkeys = try hotkeys(from: bindings, config: config)
        let result = try edit(source, hotkeys: config.hotkeys)
        guard try ConfigLoader.parse(result) == config else { throw unsupportedFormat }
        return result
    }

    public static func save(_ bindings: [KeymapBinding], to url: URL, original: String) throws {
        let originalBytes = Data(original.utf8)
        let destination = url.resolvingSymlinksInPath()
        guard try Data(contentsOf: url) == originalBytes else { throw staleFile }
        let updated = try updating(original, bindings: bindings)
        // Recheck immediately before replacing, including a symlink retargeted while preparing the edit.
        guard url.resolvingSymlinksInPath() == destination,
              try Data(contentsOf: url) == originalBytes else { throw staleFile }
        try Data(updated.utf8).write(to: destination, options: .atomic)
    }

    private static var staleFile: ConfigError {
        .validation("config file changed since it was opened; use Discard & Reload before saving")
    }

    private static var unsupportedFormat: ConfigError {
        .validation("Cannot safely edit this TOML layout. Use Open config to put keymaps in [hotkeys], [hotkeys.window], and [hotkeys.apps] tables, then reload. Inline/dotted keymap assignments are not supported.")
    }

    private static func popupValues(_ hotkeys: Config.Hotkeys) -> [(KeymapKind, String?)] {
        [(.clipboard, hotkeys.clipboard), (.emoji, hotkeys.emoji), (.windows, hotkeys.windows), (.cheatsheet, hotkeys.cheatsheet)]
    }

    private struct Replacement {
        var range: Range<Int>
        var bytes: [UInt8]
    }

    /// Edit complete assignments, not lines that merely resemble TOML headers. The parser handles
    /// quoted keys and dotted header paths; the scanner only finds statement boundaries.
    private static func edit(_ source: String, hotkeys: Config.Hotkeys) throws -> String {
        let bytes = Array(source.utf8)
        var headers: [String: Range<Int>] = [:]
        var context: [String]? = []
        var replacements: [Replacement] = []
        let popupNames = Set(popupValues(hotkeys).map { $0.0.rawValue })

        for range in statementRanges(bytes) {
            let text = String(decoding: bytes[range], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty || text.hasPrefix("#") { continue }
            let statement: TOMLTable
            do { statement = try TOMLTable(string: text) }
            catch { throw unsupportedFormat }
            if text.hasPrefix("[") {
                context = tablePath(statement)
                if let context, context == ["hotkeys"] || context == ["hotkeys", "window"] || context == ["hotkeys", "apps"] {
                    headers[context.joined(separator: ".")] = range
                }
            } else if context == [] && statement["hotkeys"] != nil {
                throw unsupportedFormat
            } else if context == ["hotkeys"] {
                if statement["window"] != nil || statement["apps"] != nil { throw unsupportedFormat }
                if statement.keys.contains(where: { popupNames.contains($0) }) {
                    replacements.append(Replacement(range: range, bytes: []))
                }
            } else if context == ["hotkeys", "window"] || context == ["hotkeys", "apps"] {
                replacements.append(Replacement(range: range, bytes: []))
            }
        }

        let bodies = [
            "hotkeys.window": hotkeys.window.keys.sorted().map { "\(quote($0)) = \(quote(hotkeys.window[$0]!))" },
            "hotkeys.apps": hotkeys.apps.keys.sorted().map { "\(quote($0)) = \(quote(hotkeys.apps[$0]!))" },
            "hotkeys": popupValues(hotkeys).compactMap { kind, value in value.map { "\(kind.rawValue) = \(quote($0))" } },
        ]
        var suffix = ""
        let newline = source.contains("\r\n") ? "\r\n" : "\n"
        for name in ["hotkeys", "hotkeys.window", "hotkeys.apps"] {
            guard let body = bodies[name], !body.isEmpty else { continue }
            let rendered = body.joined(separator: newline) + newline
            if let header = headers[name] {
                let prefix = bytes[header.upperBound - 1] == 10 ? "" : newline
                replacements.append(Replacement(range: header.upperBound..<header.upperBound, bytes: Array((prefix + rendered).utf8)))
            } else {
                suffix += newline + "[\(name)]" + newline + rendered
            }
        }
        var output = bytes
        // Delete a following assignment before inserting at the same offset.
        for replacement in replacements.sorted(by: {
            $0.range.lowerBound == $1.range.lowerBound ? $0.range.upperBound > $1.range.upperBound : $0.range.lowerBound > $1.range.lowerBound
        }) {
            output.replaceSubrange(replacement.range, with: replacement.bytes)
        }
        let result = String(decoding: output, as: UTF8.self) + suffix

        // A second, independent guard proves that unknown settings also survive, not just Config's fields.
        let expected = try TOMLTable(string: source)
        if let value = expected["hotkeys"], value.table == nil { throw unsupportedFormat }
        let expectedHotkeys = expected["hotkeys"]?.table ?? TOMLTable()
        for (name, map) in [("window", hotkeys.window), ("apps", hotkeys.apps)] {
            if let value = expectedHotkeys[name], value.table == nil { throw unsupportedFormat }
            if expectedHotkeys[name] != nil || !map.isEmpty {
                let table = TOMLTable()
                for (key, value) in map { table[key] = value }
                expectedHotkeys[name] = table
            }
        }
        for (kind, value) in popupValues(hotkeys) {
            expectedHotkeys.remove(at: kind.rawValue)
            if let value { expectedHotkeys[kind.rawValue] = value }
        }
        if expected["hotkeys"] != nil || !expectedHotkeys.isEmpty { expected["hotkeys"] = expectedHotkeys }
        let actual: TOMLTable
        do { actual = try TOMLTable(string: result) }
        catch { throw unsupportedFormat }
        guard actual == expected else { throw unsupportedFormat }
        return result
    }

    /// A standalone [header] parses as a chain of one-key tables ending in an empty table.
    /// Arrays of tables are not keymap sections, but still end the previous section's context.
    private static func tablePath(_ table: TOMLTable) -> [String]? {
        var path: [String] = []
        var current = table
        while let key = current.keys.first, current.count == 1 {
            path.append(key)
            guard let nested = current[key]?.table else { return nil }
            current = nested
        }
        return current.isEmpty ? path : nil
    }

    /// The complete document is already parsed before this runs. Track strings, escapes,
    /// comments and array/inline-table nesting so embedded newlines never split a value.
    private static func statementRanges(_ bytes: [UInt8]) -> [Range<Int>] {
        var start = bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? 3 : 0
        var index = start
        var quote: UInt8?
        var multiline = false
        var comment = false
        var depth = 0
        var ranges: [Range<Int>] = []
        while index < bytes.count {
            let byte = bytes[index]
            if let delimiter = quote {
                if delimiter == 34 && byte == 92 {
                    index += 2
                    continue
                }
                if byte == delimiter {
                    if multiline {
                        var end = index
                        while end < bytes.count && bytes[end] == delimiter { end += 1 }
                        if end - index >= 3 { quote = nil }
                        index = end
                        continue
                    }
                    quote = nil
                }
            } else if byte == 10 {
                comment = false
                if depth == 0 {
                    ranges.append(start..<(index + 1))
                    start = index + 1
                }
            } else if !comment {
                if byte == 35 { comment = true }
                else if byte == 34 || byte == 39 {
                    quote = byte
                    multiline = index + 2 < bytes.count && bytes[index + 1] == byte && bytes[index + 2] == byte
                    if multiline { index += 2 }
                } else if byte == 91 || byte == 123 { depth += 1 }
                else if byte == 93 || byte == 125 { depth -= 1 }
            }
            index += 1
        }
        if start < bytes.count { ranges.append(start..<bytes.count) }
        return ranges
    }

    private static func quote(_ value: String) -> String {
        var result = "\""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x08: result += "\\b"
            case 0x09: result += "\\t"
            case 0x0A: result += "\\n"
            case 0x0C: result += "\\f"
            case 0x0D: result += "\\r"
            case 0x22: result += "\\\""
            case 0x5C: result += "\\\\"
            case 0..<0x20, 0x7F: result += String(format: "\\u%04X", scalar.value)
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result + "\""
    }
}
