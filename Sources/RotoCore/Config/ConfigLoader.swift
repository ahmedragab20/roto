import Foundation
import TOMLKit

public enum ConfigError: Error, Equatable, CustomStringConvertible {
    case parse(String)
    case validation(String)

    public var description: String {
        switch self {
        case .parse(let message), .validation(let message):
            return message
        }
    }
}

public enum ConfigLoader {
    public static let defaultTOML = """
        [general]
        launch_at_login = false
        popup_screen = "primary"

        [window]
        gap = 0

        [window.layouts]
        editor = { x = 0.0, y = 0.0, w = 0.6, h = 1.0 }

        [hotkeys.window]
        "ctrl+alt+left" = "half-left"
        "ctrl+alt+right" = "half-right"
        "ctrl+alt+up" = "half-top"
        "ctrl+alt+down" = "half-bottom"
        "ctrl+alt+u" = "quarter-top-left"
        "ctrl+alt+i" = "quarter-top-right"
        "ctrl+alt+j" = "quarter-bottom-left"
        "ctrl+alt+k" = "quarter-bottom-right"
        "ctrl+alt+d" = "third-left"
        "ctrl+alt+f" = "third-center"
        "ctrl+alt+g" = "third-right"
        "ctrl+alt+shift+d" = "two-thirds-left"
        "ctrl+alt+shift+g" = "two-thirds-right"
        "ctrl+alt+enter" = "maximize"
        "ctrl+alt+shift+enter" = "almost-maximize"
        "ctrl+alt+c" = "center"
        "ctrl+alt+cmd+right" = "next-display"
        "ctrl+alt+cmd+left" = "prev-display"
        "ctrl+alt+shift+h" = "focus-left"
        "ctrl+alt+shift+l" = "focus-right"
        "ctrl+alt+shift+k" = "focus-up"
        "ctrl+alt+shift+j" = "focus-down"
        "ctrl+alt+shift+right" = "focus-next-display"
        "ctrl+alt+shift+left" = "focus-prev-display"
        "ctrl+alt+e" = "layout:editor"

        [hotkeys.apps]
        "ctrl+alt+t" = "com.apple.Terminal"
        "ctrl+alt+b" = "Safari"

        [hotkeys]
        clipboard = "ctrl+alt+v"
        emoji = "ctrl+alt+period"
        windows = "ctrl+alt+w"
        cheatsheet = "ctrl+alt+slash"

        [apps]
        when_focused = "cycle"

        [clipboard]
        history_size = 200
        max_age_days = 60
        persist = true
        include_images = true
        ignore_apps = ["com.1password.1password"]

        [emoji]
        skin_tone = "default"
        """

    public static var builtin: Config {
        (try? parse(defaultTOML)) ?? Config()
    }

    public static func parse(_ toml: String) throws -> Config {
        let table: TOMLTable
        do {
            table = try TOMLTable(string: toml)
        } catch let error as TOMLParseError {
            let begin = error.source.begin
            throw ConfigError.parse("TOML parse error at line \(begin.line): \(error)")
        } catch {
            throw ConfigError.parse(String(describing: error))
        }

        var config = Config()
        var errors: [String] = []

        if let general = table["general"]?.table {
            if let value = general["launch_at_login"] {
                if let flag = value.bool {
                    config.general.launchAtLogin = flag
                } else {
                    errors.append("general.launch_at_login must be a boolean")
                }
            }
            if let value = general["popup_screen"] {
                if let string = value.string, let screen = PopupScreen(rawValue: string) {
                    config.general.popupScreen = screen
                } else {
                    errors.append("general.popup_screen must be primary, cursor, or frontmost")
                }
            }
        }

        if let window = table["window"]?.table {
            if let value = window["gap"] {
                if let number = doubleValue(value) {
                    config.window.gap = number
                } else {
                    errors.append("window.gap must be a number")
                }
            }
            if let layouts = window["layouts"]?.table {
                var parsed: [String: FractionalRect] = [:]
                for key in layouts.keys {
                    guard let entry = layouts[key]?.table else {
                        errors.append("window.layouts.\(key) must be a table { x, y, w, h }")
                        continue
                    }
                    if let rect = fractionalRect(entry) {
                        parsed[key] = rect
                    } else {
                        errors.append("window.layouts.\(key) needs numeric x, y, w, h")
                    }
                }
                config.window.layouts = parsed
            }
        }

        if let hotkeys = table["hotkeys"]?.table {
            if let window = hotkeys["window"]?.table {
                config.hotkeys.window = stringMap(window, path: "hotkeys.window", errors: &errors)
            }
            if let apps = hotkeys["apps"]?.table {
                config.hotkeys.apps = stringMap(apps, path: "hotkeys.apps", errors: &errors)
            }
            if let value = hotkeys["clipboard"] {
                if let string = value.string {
                    config.hotkeys.clipboard = string
                } else {
                    errors.append("hotkeys.clipboard must be a string")
                }
            }
            if let value = hotkeys["emoji"] {
                if let string = value.string {
                    config.hotkeys.emoji = string
                } else {
                    errors.append("hotkeys.emoji must be a string")
                }
            }
            if let value = hotkeys["windows"] {
                if let string = value.string {
                    config.hotkeys.windows = string
                } else {
                    errors.append("hotkeys.windows must be a string")
                }
            }
            if let value = hotkeys["cheatsheet"] {
                if let string = value.string {
                    config.hotkeys.cheatsheet = string
                } else {
                    errors.append("hotkeys.cheatsheet must be a string")
                }
            }
        }

        if let apps = table["apps"]?.table {
            if let value = apps["when_focused"] {
                if let string = value.string, let behavior = AppFocusBehavior(rawValue: string) {
                    config.apps.whenFocused = behavior
                } else {
                    errors.append("apps.when_focused must be cycle, hide, or none")
                }
            }
        }

        if let clipboard = table["clipboard"]?.table {
            if let value = clipboard["history_size"] {
                if let int = intValue(value) {
                    config.clipboard.historySize = int
                } else {
                    errors.append("clipboard.history_size must be an integer")
                }
            }
            if let value = clipboard["max_age_days"] {
                if let int = intValue(value) {
                    config.clipboard.maxAgeDays = int
                } else {
                    errors.append("clipboard.max_age_days must be an integer")
                }
            }
            if let value = clipboard["persist"] {
                if let flag = value.bool {
                    config.clipboard.persist = flag
                } else {
                    errors.append("clipboard.persist must be a boolean")
                }
            }
            if let value = clipboard["include_images"] {
                if let flag = value.bool {
                    config.clipboard.includeImages = flag
                } else {
                    errors.append("clipboard.include_images must be a boolean")
                }
            }
            if let value = clipboard["ignore_apps"] {
                if let array = value.array {
                    var ids: [String] = []
                    for item in array {
                        if let string = item.string {
                            ids.append(string)
                        } else {
                            errors.append("clipboard.ignore_apps entries must be strings")
                        }
                    }
                    config.clipboard.ignoreApps = ids
                } else {
                    errors.append("clipboard.ignore_apps must be an array of strings")
                }
            }
        }

        if let emoji = table["emoji"]?.table {
            if let value = emoji["skin_tone"] {
                if let string = value.string {
                    config.emoji.skinTone = string
                } else {
                    errors.append("emoji.skin_tone must be a string")
                }
            }
        }

        errors.append(contentsOf: validate(config))
        if !errors.isEmpty {
            throw ConfigError.validation(errors.joined(separator: "; "))
        }
        return config
    }

    public static func load(from url: URL) throws -> Config {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ConfigError.parse("could not read \(url.path): \(error.localizedDescription)")
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw ConfigError.parse("\(url.path) is not UTF-8")
        }
        return try parse(text)
    }

    public static func bindings(in config: Config) throws -> [(KeyCombo, BoundAction)] {
        var result: [(KeyCombo, BoundAction)] = []
        var seen: [String: String] = [:]

        func add(_ raw: String, _ action: BoundAction, origin: String) throws {
            let combo = try KeyCombo.parse(raw)
            if let previous = seen[combo.canonical] {
                throw ConfigError.validation("hotkey '\(combo.canonical)' is bound twice (\(previous) and \(origin))")
            }
            seen[combo.canonical] = origin
            result.append((combo, action))
        }

        for (combo, action) in config.hotkeys.window {
            let command = try Layout.resolveWindowCommand(action, layouts: config.window.layouts)
            try add(combo, .window(command), origin: "hotkeys.window")
        }
        for (combo, target) in config.hotkeys.apps {
            if target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ConfigError.validation("hotkeys.apps '\(combo)' has an empty app")
            }
            try add(combo, .app(target), origin: "hotkeys.apps")
        }
        if let raw = config.hotkeys.clipboard {
            try add(raw, .clipboard, origin: "hotkeys.clipboard")
        }
        if let raw = config.hotkeys.emoji {
            try add(raw, .emoji, origin: "hotkeys.emoji")
        }
        if let raw = config.hotkeys.windows {
            try add(raw, .windows, origin: "hotkeys.windows")
        }
        if let raw = config.hotkeys.cheatsheet {
            try add(raw, .cheatsheet, origin: "hotkeys.cheatsheet")
        }
        return result
    }

    private static func validate(_ config: Config) -> [String] {
        var errors: [String] = []
        if config.window.gap < 0 {
            errors.append("window.gap must be >= 0")
        }
        if config.clipboard.historySize < 1 {
            errors.append("clipboard.history_size must be >= 1")
        }
        if config.clipboard.maxAgeDays < 0 {
            errors.append("clipboard.max_age_days must be >= 0")
        }
        if SkinTone(rawValue: config.emoji.skinTone) == nil {
            errors.append(
                "emoji.skin_tone must be one of default, light, medium-light, medium, medium-dark, dark"
            )
        }
        for (name, rect) in config.window.layouts {
            if rect.w <= 0 || rect.h <= 0 {
                errors.append("window.layouts.\(name) width and height must be > 0")
            }
        }
        do {
            _ = try bindings(in: config)
        } catch let error as ConfigError {
            errors.append(error.description)
        } catch {
            errors.append(String(describing: error))
        }
        return errors
    }

    private static func stringMap(_ table: TOMLTable, path: String, errors: inout [String]) -> [String: String] {
        var result: [String: String] = [:]
        for key in table.keys {
            if let string = table[key]?.string {
                result[key] = string
            } else {
                errors.append("\(path).\(key) must be a string")
            }
        }
        return result
    }

    private static func fractionalRect(_ table: TOMLTable) -> FractionalRect? {
        guard let x = table["x"].flatMap({ doubleValue($0) }),
              let y = table["y"].flatMap({ doubleValue($0) }),
              let w = table["w"].flatMap({ doubleValue($0) }),
              let h = table["h"].flatMap({ doubleValue($0) })
        else { return nil }
        return FractionalRect(x: x, y: y, w: w, h: h)
    }

    private static func doubleValue(_ value: any TOMLValueConvertible) -> Double? {
        if let d = value.double { return d }
        if let i = value.int { return Double(i) }
        return nil
    }

    private static func intValue(_ value: any TOMLValueConvertible) -> Int? {
        if let i = value.int { return i }
        if let d = value.double, d.rounded() == d { return Int(d) }
        return nil
    }
}
