import Foundation

public struct KeyCombo: Hashable, Sendable, Equatable {
    public var keyCode: UInt32
    public var carbonModifiers: UInt32
    public var keyName: String
    public var canonical: String

    public init(keyCode: UInt32, carbonModifiers: UInt32, keyName: String, canonical: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.keyName = keyName
        self.canonical = canonical
    }

    // Carbon Event Manager modifier bits (cmdKey, shiftKey, optionKey, controlKey).
    public static let cmdBit: UInt32 = 1 << 8
    public static let shiftBit: UInt32 = 1 << 9
    public static let optionBit: UInt32 = 1 << 11
    public static let controlBit: UInt32 = 1 << 12

    public static func parse(_ raw: String) throws -> KeyCombo {
        let parts = raw.split(separator: "+").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else {
            throw ConfigError.validation("empty hotkey")
        }

        var control = false
        var option = false
        var command = false
        var shift = false
        var key: String?

        for part in parts {
            switch part {
            case "ctrl", "control":
                control = true
            case "alt", "opt", "option":
                option = true
            case "cmd", "command", "super":
                command = true
            case "shift":
                shift = true
            default:
                if key != nil {
                    throw ConfigError.validation("hotkey '\(raw)' has more than one key")
                }
                key = part
            }
        }

        guard let key else {
            throw ConfigError.validation("hotkey '\(raw)' is missing a key")
        }
        guard control || option || command || shift else {
            throw ConfigError.validation("hotkey '\(raw)' needs at least one modifier")
        }
        guard let keyCode = KeyCodes.code(for: key) else {
            throw ConfigError.validation("unknown key '\(key)' in hotkey '\(raw)'")
        }

        var mods: UInt32 = 0
        if control { mods |= controlBit }
        if option { mods |= optionBit }
        if command { mods |= cmdBit }
        if shift { mods |= shiftBit }

        var tokens: [String] = []
        if control { tokens.append("ctrl") }
        if option { tokens.append("alt") }
        if shift { tokens.append("shift") }
        if command { tokens.append("cmd") }
        tokens.append(key)
        let canonical = tokens.joined(separator: "+")

        return KeyCombo(keyCode: keyCode, carbonModifiers: mods, keyName: key, canonical: canonical)
    }
}
