import Foundation
import Testing
@testable import RotoCore

struct ConfigLoaderTests {
    @Test func parsesBuiltinDefaults() throws {
        let config = try ConfigLoader.parse(ConfigLoader.defaultTOML)
        #expect(config.general.launchAtLogin == false)
        #expect(config.window.gap == 0)
        #expect(config.window.layouts["editor"]?.w == 0.6)
        #expect(config.hotkeys.window["ctrl+alt+left"] == "half-left")
        #expect(config.hotkeys.window["ctrl+alt+shift+c"] == "center-large")
        #expect(config.hotkeys.apps["ctrl+alt+t"] == "com.apple.Terminal")
        #expect(config.hotkeys.clipboard == "ctrl+alt+v")
        #expect(config.hotkeys.emoji == "ctrl+alt+period")
        #expect(config.clipboard.historySize == 200)
        #expect(config.clipboard.persist == true)
        #expect(config.clipboard.maxAgeDays == 60)
        #expect(config.clipboard.ignoreApps.contains("com.1password.1password"))
        #expect(config.emoji.skinTone == "default")
        #expect(config.general.popupScreen == .primary)
        let bindings = try ConfigLoader.bindings(in: config)
        #expect(!bindings.isEmpty)
        #expect(bindings.contains { if case .clipboard = $0.1 { return true } else { return false } })
    }

    @Test func overlaysPartialConfig() throws {
        let toml = """
            [window]
            gap = 8
            [hotkeys.window]
            "ctrl+alt+left" = "half-right"
            """
        let config = try ConfigLoader.parse(toml)
        #expect(config.window.gap == 8)
        #expect(config.hotkeys.window["ctrl+alt+left"] == "half-right")
        #expect(config.clipboard.historySize == 200)
    }

    @Test func rejectsUnknownAction() {
        let toml = """
            [hotkeys.window]
            "ctrl+alt+left" = "explode"
            """
        #expect(throws: ConfigError.self) {
            try ConfigLoader.parse(toml)
        }
    }

    @Test func rejectsUnknownLayoutReference() {
        let toml = """
            [hotkeys.window]
            "ctrl+alt+e" = "layout:missing"
            """
        #expect(throws: ConfigError.self) {
            try ConfigLoader.parse(toml)
        }
    }

    @Test func rejectsDuplicateHotkeys() {
        let toml = """
            [hotkeys.window]
            "ctrl+alt+v" = "maximize"
            [hotkeys]
            clipboard = "ctrl+alt+v"
            """
        #expect(throws: ConfigError.self) {
            try ConfigLoader.parse(toml)
        }
    }

    @Test(arguments: [(".", "period"), ("return", "enter"), ("backspace", "delete")])
    func rejectsPhysicalAliasCollisions(alias: String, name: String) {
        let toml = """
            [hotkeys]
            emoji = "ctrl+alt+\(name)"
            [hotkeys.window]
            "ctrl+alt+\(alias)" = "center"
            """
        #expect(throws: ConfigError.self) { try ConfigLoader.parse(toml) }
    }

    @Test(arguments: ["hotkeys = 'bad'", "[hotkeys]\nwindow = 'bad'", "[hotkeys]\napps = ['bad']", "window = 42", "apps = false"])
    func rejectsMalformedKeymapTables(source: String) {
        #expect(throws: ConfigError.self) { try ConfigLoader.parse(source) }
    }

    @Test func allowsEmptyKeymapTablesAndDistinctModifierChords() throws {
        let empty = try ConfigLoader.parse("[hotkeys.window]\n[hotkeys.apps]\n")
        #expect(try ConfigLoader.bindings(in: empty).isEmpty)
        let distinct = try ConfigLoader.parse("[hotkeys.apps]\n'ctrl+.' = 'A'\n'ctrl+shift+period' = 'B'\n")
        #expect(try ConfigLoader.bindings(in: distinct).count == 2)
    }

    @Test func rejectsNegativeMaxAge() {
        let toml = """
            [clipboard]
            max_age_days = -1
            """
        #expect(throws: ConfigError.self) {
            try ConfigLoader.parse(toml)
        }
    }

    @Test func rejectsBadSkinTone() {
        let toml = """
            [emoji]
            skin_tone = "blue"
            """
        #expect(throws: ConfigError.self) {
            try ConfigLoader.parse(toml)
        }
    }

    @Test func rejectsInvalidTOML() {
        #expect(throws: ConfigError.self) {
            try ConfigLoader.parse("hotkeys.window = [")
        }
    }

    @Test func integerGapIsAccepted() throws {
        let config = try ConfigLoader.parse("[window]\ngap = 12")
        #expect(config.window.gap == 12)
    }

    @Test func parsesPopupScreen() throws {
        let config = try ConfigLoader.parse("[general]\npopup_screen = \"cursor\"")
        #expect(config.general.popupScreen == .cursor)
    }

    @Test func rejectsBadPopupScreen() {
        #expect(throws: ConfigError.self) {
            try ConfigLoader.parse("[general]\npopup_screen = \"other\"")
        }
    }

    @Test func parsesAppsAndPopupHotkeys() throws {
        let toml = """
            [hotkeys.apps]                       # bundle id, app name, or path to an .app
            "ctrl+alt+b" = "net.imput.helium"     # Helium
            "ctrl+alt+t" = "com.mitchellh.ghostty" # Ghostty

            [hotkeys]
            windows = "ctrl+alt+w"
            cheatsheet = "ctrl+alt+slash"

            [apps]
            when_focused = "hide"
            """
        let config = try ConfigLoader.parse(toml)
        #expect(config.hotkeys.apps["ctrl+alt+b"] == "net.imput.helium")
        #expect(config.hotkeys.windows == "ctrl+alt+w")
        #expect(config.hotkeys.cheatsheet == "ctrl+alt+slash")
        #expect(config.apps.whenFocused == .hide)
        let bindings = try ConfigLoader.bindings(in: config)
        #expect(bindings.contains { $0.1 == .windows })
        #expect(bindings.contains { $0.1 == .cheatsheet })
        #expect(bindings.contains { $0.1 == .app("com.mitchellh.ghostty") })
    }

    @Test func builtinDefaultsBindWindowsAndCheatsheet() throws {
        let config = try ConfigLoader.parse(ConfigLoader.defaultTOML)
        #expect(config.hotkeys.windows == "ctrl+alt+w")
        #expect(config.hotkeys.cheatsheet == "ctrl+alt+slash")
        #expect(config.apps.whenFocused == .cycle)
    }

    @Test func bundledDefaultConfigParses() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appendingPathComponent("Sources/Roto/Resources/config.default.toml")
        let config = try ConfigLoader.load(from: url)
        #expect(config.hotkeys.windows == "ctrl+alt+w")
        #expect(config.apps.whenFocused == .cycle)
    }

    @Test func whenFocusedNoneMeansNothing() throws {
        let config = try ConfigLoader.parse("[apps]\nwhen_focused = \"none\"")
        #expect(config.apps.whenFocused == .nothing)
    }

    @Test func rejectsBadWhenFocused() {
        #expect(throws: ConfigError.self) {
            try ConfigLoader.parse("[apps]\nwhen_focused = \"explode\"")
        }
    }

    @Test func rejectsPopupHotkeyClash() {
        #expect(throws: ConfigError.self) {
            try ConfigLoader.parse("[hotkeys]\nwindows = \"ctrl+alt+v\"\nclipboard = \"ctrl+alt+v\"")
        }
    }
}
