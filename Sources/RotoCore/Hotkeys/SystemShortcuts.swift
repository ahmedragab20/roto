import Foundation

/// macOS shortcuts that win over any app's hotkey while they are turned on.
public enum SystemShortcuts {
    public struct Shortcut: Sendable, Equatable {
        public var id: Int
        public var title: String
        public var keyCode: UInt32
        /// NSEvent modifier flags, as macOS stores them.
        public var modifiers: UInt32
    }

    /// Spotlight's own shortcuts, with their factory keys (⌘Space, ⌥⌘Space).
    public static let spotlight: [Shortcut] = [
        Shortcut(id: 64, title: "Show Spotlight search", keyCode: 49, modifiers: 1 << 20),
        Shortcut(id: 65, title: "Show Finder search window", keyCode: 49, modifiers: (1 << 19) | (1 << 20)),
    ]

    /// The enabled Spotlight shortcut that would swallow `combo`, if any.
    ///
    /// `table` is the `AppleSymbolicHotKeys` dictionary from the
    /// `com.apple.symbolichotkeys` domain. A shortcut missing from it was never
    /// changed, so it is on with its factory keys.
    public static func spotlightConflict(with combo: KeyCombo, table: [String: Any]?) -> Shortcut? {
        for shortcut in spotlight {
            var current = shortcut
            if let entry = table?[String(shortcut.id)] as? [String: Any] {
                if (entry["enabled"] as? NSNumber)?.boolValue == false { continue }
                if let value = entry["value"] as? [String: Any],
                   let parameters = value["parameters"] as? [NSNumber], parameters.count >= 3 {
                    current.keyCode = parameters[1].uint32Value
                    current.modifiers = parameters[2].uint32Value
                }
            }
            if current.keyCode == combo.keyCode && carbonModifiers(current.modifiers) == combo.carbonModifiers {
                return current
            }
        }
        return nil
    }

    static func carbonModifiers(_ flags: UInt32) -> UInt32 {
        var carbon: UInt32 = 0
        if flags & (1 << 17) != 0 { carbon |= KeyCombo.shiftBit }
        if flags & (1 << 18) != 0 { carbon |= KeyCombo.controlBit }
        if flags & (1 << 19) != 0 { carbon |= KeyCombo.optionBit }
        if flags & (1 << 20) != 0 { carbon |= KeyCombo.cmdBit }
        return carbon
    }
}
