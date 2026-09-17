import Foundation

public struct ShortcutEntry: Sendable, Equatable, Identifiable {
    /// Display form, e.g. "⌃⌥←".
    public var keys: String
    public var title: String
    /// Bundle id or app name for app shortcuts, so the UI can show the app.
    public var appTarget: String?
    /// Typed form, e.g. "ctrl+alt+left", so searching "ctrl alt" works.
    public var combo: String?

    public var id: String { "\(keys)|\(title)" }

    public init(keys: String, title: String, appTarget: String? = nil, combo: String? = nil) {
        self.keys = keys
        self.title = title
        self.appTarget = appTarget
        self.combo = combo
    }
}

public struct ShortcutSection: Sendable, Equatable, Identifiable {
    public var title: String
    public var entries: [ShortcutEntry]

    public var id: String { title }

    public init(title: String, entries: [ShortcutEntry]) {
        self.title = title
        self.entries = entries
    }
}

/// Everything roto answers to, built from the live config.
public enum Cheatsheet {
    public static func sections(for config: Config) -> [ShortcutSection] {
        var sections: [ShortcutSection] = []

        let popups: [(String?, String)] = [
            (config.hotkeys.clipboard, "Clipboard history"),
            (config.hotkeys.emoji, "Emoji picker"),
            (config.hotkeys.windows, "Switch windows"),
            (config.hotkeys.cheatsheet, "Keyboard shortcuts"),
        ]
        let popupEntries = popups.compactMap { raw, title in
            raw.flatMap { entry($0, title: title) }
        }
        sections.append(ShortcutSection(title: "Popups", entries: popupEntries))

        let apps = config.hotkeys.apps
            .compactMap { raw, target in entry(raw, title: target, appTarget: target) }
            .sorted { $0.keys < $1.keys }
        sections.append(ShortcutSection(title: "Apps", entries: apps))

        var layout: [(rank: Int, entry: ShortcutEntry)] = []
        var displays: [(rank: Int, entry: ShortcutEntry)] = []
        var focus: [(rank: Int, entry: ShortcutEntry)] = []
        for (raw, action) in config.hotkeys.window {
            let name = action.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let item = entry(raw, title: describe(windowAction: name)) else { continue }
            let rank = actionOrder.firstIndex(of: name) ?? actionOrder.count
            if name.hasPrefix("focus-") {
                focus.append((rank, item))
            } else if name.hasSuffix("-display") {
                displays.append((rank, item))
            } else {
                layout.append((rank, item))
            }
        }
        for (title, items) in [("Window layout", layout), ("Displays", displays), ("Window focus", focus)] {
            let ordered = items
                .sorted { $0.rank != $1.rank ? $0.rank < $1.rank : $0.entry.title < $1.entry.title }
                .map(\.entry)
            sections.append(ShortcutSection(title: title, entries: ordered))
        }

        return sections.filter { !$0.entries.isEmpty } + popupKeys
    }

    /// "ctrl+alt+shift+left" → "⌃⌥⇧←", in the order macOS menus use.
    public static func displayKeys(_ combo: KeyCombo) -> String {
        var text = ""
        if combo.carbonModifiers & KeyCombo.controlBit != 0 { text += "⌃" }
        if combo.carbonModifiers & KeyCombo.optionBit != 0 { text += "⌥" }
        if combo.carbonModifiers & KeyCombo.shiftBit != 0 { text += "⇧" }
        if combo.carbonModifiers & KeyCombo.cmdBit != 0 { text += "⌘" }
        return text + keyGlyph(combo.keyName)
    }

    public static func keyGlyph(_ name: String) -> String {
        if let glyph = keyGlyphs[name] {
            return glyph
        }
        if name.hasPrefix("numpad") {
            return "Num " + keyGlyph(String(name.dropFirst("numpad".count)))
        }
        return name.count == 1 ? name.uppercased() : name.capitalized
    }

    public static func describe(windowAction name: String) -> String {
        if let title = actionTitles[name] {
            return title
        }
        if name.hasPrefix("layout:") {
            return "Layout “\(name.dropFirst("layout:".count))”"
        }
        return name
    }

    private static func entry(_ raw: String, title: String, appTarget: String? = nil) -> ShortcutEntry? {
        guard let combo = try? KeyCombo.parse(raw) else { return nil }
        return ShortcutEntry(keys: displayKeys(combo), title: title, appTarget: appTarget, combo: combo.canonical)
    }

    private static let actionOrder = [
        "half-left", "half-right", "half-top", "half-bottom",
        "quarter-top-left", "quarter-top-right", "quarter-bottom-left", "quarter-bottom-right",
        "third-left", "third-center", "third-right", "two-thirds-left", "two-thirds-right",
        "maximize", "almost-maximize", "center-large", "center",
        "next-display", "prev-display",
        "focus-left", "focus-right", "focus-up", "focus-down", "focus-next-display", "focus-prev-display",
    ]

    private static let actionTitles: [String: String] = [
        "half-left": "Left half",
        "half-right": "Right half",
        "half-top": "Top half",
        "half-bottom": "Bottom half",
        "quarter-top-left": "Top-left quarter",
        "quarter-top-right": "Top-right quarter",
        "quarter-bottom-left": "Bottom-left quarter",
        "quarter-bottom-right": "Bottom-right quarter",
        "third-left": "Left third",
        "third-center": "Center third",
        "third-right": "Right third",
        "two-thirds-left": "Left two thirds",
        "two-thirds-right": "Right two thirds",
        "maximize": "Maximize",
        "almost-maximize": "Almost maximize",
        "center-large": "Center, large",
        "center": "Center, keep size",
        "next-display": "Move window to next display",
        "prev-display": "Move window to previous display",
        "focus-left": "Focus window to the left",
        "focus-right": "Focus window to the right",
        "focus-up": "Focus window above",
        "focus-down": "Focus window below",
        "focus-next-display": "Focus next display",
        "focus-prev-display": "Focus previous display",
    ]

    private static let keyGlyphs: [String: String] = [
        "left": "←", "right": "→", "up": "↑", "down": "↓",
        "enter": "↩", "return": "↩", "tab": "⇥", "space": "Space",
        "escape": "⎋", "esc": "⎋", "delete": "⌫", "backspace": "⌫", "forwarddelete": "⌦",
        "home": "↖", "end": "↘", "pageup": "⇞", "pagedown": "⇟", "help": "Help",
        "period": ".", "comma": ",", "slash": "/", "backslash": "\\", "semicolon": ";",
        "quote": "'", "grave": "`", "minus": "-", "equal": "=",
        "leftbracket": "[", "rightbracket": "]",
        "clear": "Clear", "decimal": ".", "multiply": "*", "plus": "+", "divide": "/", "equals": "=",
    ]

    /// Keys that work inside each popup. Keep in sync with the panel key handlers.
    public static let popupKeys: [ShortcutSection] = [
        ShortcutSection(title: "In clipboard history", entries: [
            ShortcutEntry(keys: "↩", title: "Paste into the app you were in"),
            ShortcutEntry(keys: "⌘↩", title: "Copy without pasting"),
            ShortcutEntry(keys: "⌘C", title: "Copy entry (when no search text is selected)"),
            ShortcutEntry(keys: "⌘1 – ⌘9", title: "Paste entry 1–9"),
            ShortcutEntry(keys: "⌘⌫", title: "Delete entry"),
            ShortcutEntry(keys: "⌘Y", title: "Quick Look image or file"),
            ShortcutEntry(keys: "⌘O", title: "Open image or file in its app"),
            ShortcutEntry(keys: "↑ ↓  ⌃P ⌃N", title: "Move selection"),
            ShortcutEntry(keys: "⌘↑ ⌘↓", title: "First / last entry"),
            ShortcutEntry(keys: "⎋", title: "Clear search, then close"),
        ]),
        ShortcutSection(title: "In emoji picker", entries: [
            ShortcutEntry(keys: "↩", title: "Type emoji into the app you were in"),
            ShortcutEntry(keys: "⌘↩", title: "Copy emoji"),
            ShortcutEntry(keys: "← → ↑ ↓", title: "Move in the grid"),
            ShortcutEntry(keys: "⇥ ⇧⇥", title: "Next / previous group"),
            ShortcutEntry(keys: "⎋", title: "Clear search, then close"),
        ]),
        ShortcutSection(title: "In window switcher", entries: [
            ShortcutEntry(keys: "↩", title: "Switch to window"),
            ShortcutEntry(keys: "⌘1 – ⌘9", title: "Switch to window 1–9"),
            ShortcutEntry(keys: "⌘W", title: "Close window"),
            ShortcutEntry(keys: "⌘M", title: "Minimize or restore window"),
            ShortcutEntry(keys: "⌘H", title: "Hide app"),
            ShortcutEntry(keys: "⌘Q", title: "Quit app"),
            ShortcutEntry(keys: "↑ ↓  ⌃P ⌃N", title: "Move selection"),
            ShortcutEntry(keys: "⎋", title: "Clear search, then close"),
        ]),
        ShortcutSection(title: "In this sheet", entries: [
            ShortcutEntry(keys: "⌘,", title: "Customize shortcuts"),
            ShortcutEntry(keys: "⎋", title: "Clear search, then close"),
        ]),
    ]
}
