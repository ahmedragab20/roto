import Foundation
import Testing
@testable import RotoCore

struct KeymapEditorTests {
    @Test func readsAndBuildsEveryKind() throws {
        let config = try ConfigLoader.parse("""
            [window.layouts]
            custom = { x = 0, y = 0, w = 1, h = 1 }
            [hotkeys.window]
            "ctrl+alt+a" = "layout:custom"
            [hotkeys.apps]
            "ctrl+alt+b" = "com.example.App"
            [hotkeys]
            clipboard = "ctrl+alt+c"
            emoji = "ctrl+alt+d"
            windows = "ctrl+alt+e"
            cheatsheet = "ctrl+alt+f"
            """)
        let rows = KeymapEditor.bindings(in: config)
        #expect(Set(rows.map(\.kind)) == Set(KeymapKind.allCases))
        let result = try KeymapEditor.hotkeys(from: rows, config: config)
        #expect(result == config.hotkeys)
    }

    @Test func editsAndRemovesBindingsWhilePreservingOtherText() throws {
        let source = """
            # keep this comment
            [general]
            launch_at_login = true
            [hotkeys.window]
            "ctrl+alt+a" = "center"
            [hotkeys]
            clipboard = "ctrl+alt+c"
            unknown_setting = 42
            """
        let rows = [KeymapBinding(kind: .window, shortcut: "ctrl+alt+b", target: "center-large"), KeymapBinding(kind: .clipboard, shortcut: "ctrl+alt+d")]
        let updated = try KeymapEditor.updating(source, bindings: rows)
        #expect(updated.contains("# keep this comment"))
        #expect(updated.contains("unknown_setting = 42"))
        #expect(updated.contains("ctrl+alt+b"))
        #expect(!updated.contains("ctrl+alt+a"))
        #expect(try ConfigLoader.parse(updated).hotkeys.clipboard == "ctrl+alt+d")
    }

    @Test func rejectsPhysicalAliasesAndInvalidRows() throws {
        let config = Config()
        let duplicate = [KeymapBinding(kind: .window, shortcut: "ctrl+alt+return", target: "center"), KeymapBinding(kind: .app, shortcut: "ctrl+alt+enter", target: "App")]
        #expect(throws: ConfigError.self) { try KeymapEditor.hotkeys(from: duplicate, config: config) }
        let periodDuplicate = [KeymapBinding(kind: .window, shortcut: "ctrl+alt+.", target: "center"), KeymapBinding(kind: .app, shortcut: "ctrl+alt+period", target: "App")]
        #expect(throws: ConfigError.self) { try KeymapEditor.hotkeys(from: periodDuplicate, config: config) }
        #expect(throws: ConfigError.self) { try KeymapEditor.hotkeys(from: [KeymapBinding(kind: .app, shortcut: "ctrl+alt+a")], config: config) }
        #expect(throws: ConfigError.self) { try KeymapEditor.hotkeys(from: [KeymapBinding(kind: .window, shortcut: "ctrl+alt+a", target: "missing")], config: config) }
    }

    @Test func draftAliasesNeverHideExistingBindings() {
        // An in-memory draft can still contain conflicts even though the file loader rejects them.
        var config = Config()
        config.hotkeys.apps = ["ctrl+enter": "A", "ctrl+return": "B"]
        #expect(KeymapEditor.bindings(in: config).count == 2)
    }

    @Test func preservesMultilineStringsThatLookLikeKeymaps() throws {
        let source = "[notes]\ntext = '''\n[hotkeys]\nclipboard = \"ctrl+alt+c\"\n'''\n[general]\npopup_screen = \"cursor\"\n"
        #expect(try KeymapEditor.updating(source, bindings: []) == source)
    }

    @Test func supportsQuotedHeadersAndLiteralKeys() throws {
        let source = "[ 'hotkeys' . 'apps' ] # keep header\n'ctrl+alt+a' = 'Old'\n# keep comment\n[ 'general' ]\npopup_screen = 'cursor'\n"
        let rows = [KeymapBinding(kind: .app, shortcut: "ctrl+alt+b", target: "New")]
        let updated = try KeymapEditor.updating(source, bindings: rows)
        #expect(try ConfigLoader.parse(updated).hotkeys.apps == ["ctrl+alt+b": "New"])
        #expect(updated.contains("# keep header"))
        #expect(updated.contains("# keep comment"))
        #expect(updated.contains("[ 'general' ]\npopup_screen = 'cursor'\n"))
    }

    @Test func rejectsUnsupportedInlineAndDottedKeymapsWithoutIgnoringEdits() {
        for source in ["hotkeys.clipboard = 'ctrl+alt+c'", "hotkeys = { clipboard = 'ctrl+alt+c' }"] {
            #expect(throws: ConfigError.self) { try KeymapEditor.updating(source, bindings: []) }
        }
    }

    @Test func rewritesAllKindsAndPreservesUnrelatedTOMLVerbatim() throws {
        let extra = """

            [future]
            # quotes in comments: ''' and \"\"\"
            data = [
              { text = '[hotkeys.window]', enabled = true },
              { text = 'clipboard = 12', enabled = false },
            ]
            [[future.items]]
            name = 'untouched'
            """
        let source = ConfigLoader.defaultTOML + extra
        let rows = [
            KeymapBinding(kind: .window, shortcut: "ctrl+1", target: "layout:editor"),
            KeymapBinding(kind: .app, shortcut: "ctrl+2", target: "App\\Name\"\t\r\n\u{1}\u{7F}"),
            KeymapBinding(kind: .clipboard, shortcut: "ctrl+3"),
            KeymapBinding(kind: .emoji, shortcut: "ctrl+4"),
            KeymapBinding(kind: .windows, shortcut: "ctrl+5"),
            KeymapBinding(kind: .cheatsheet, shortcut: "ctrl+6"),
        ]
        var expected = try ConfigLoader.parse(source)
        expected.hotkeys = try KeymapEditor.hotkeys(from: rows, config: expected)
        let updated = try KeymapEditor.updating(source, bindings: rows)
        #expect(try ConfigLoader.parse(updated) == expected)
        #expect(updated.contains(extra))
    }

    @Test func preservesUnknownMultilineValuesInsideHotkeysAndCRLF() throws {
        let source = "[hotkeys]\r\nnotes = '''\r\nclipboard = 42\r\n[hotkeys.apps]\r\n'''\r\nemoji = 'ctrl+e'\r\n"
        let updated = try KeymapEditor.updating(source, bindings: [KeymapBinding(kind: .emoji, shortcut: "ctrl+m")])
        #expect(updated.contains("notes = '''\r\nclipboard = 42\r\n[hotkeys.apps]\r\n'''\r\n"))
        #expect(updated.contains("emoji = \"ctrl+m\"\r\n"))
        #expect(try ConfigLoader.parse(updated).hotkeys.emoji == "ctrl+m")
    }

    @Test func canCreateBindingsInAnEmptyFileAndUseEqualsKey() throws {
        let rows = [KeymapBinding(kind: .app, shortcut: "ctrl+=", target: "App")]
        let initial = try KeymapEditor.updating("", bindings: rows)
        #expect(try ConfigLoader.parse(initial).hotkeys.apps == ["ctrl+=": "App"])
        #expect(try ConfigLoader.parse(KeymapEditor.updating(initial, bindings: [])).hotkeys == Config.Hotkeys())
    }

    @Test func windowChoicesCoverEveryActionAndCustomLayout() throws {
        let config = ConfigLoader.builtin
        let choices = Set(KeymapEditor.windowActions(in: config))
        #expect(choices.isSuperset(of: Set(config.hotkeys.window.values)))
        #expect(choices.isSuperset(of: Set(Layout.presets.keys)))
        for action in choices { _ = try Layout.resolveWindowCommand(action, layouts: config.window.layouts) }
    }

    @Test func removesAllBindingsAndRejectsDuplicatePopups() throws {
        let updated = try KeymapEditor.updating(ConfigLoader.defaultTOML, bindings: [])
        #expect(try ConfigLoader.parse(updated).hotkeys == Config.Hotkeys())
        let rows = [KeymapBinding(kind: .emoji, shortcut: "ctrl+a"), KeymapBinding(kind: .emoji, shortcut: "ctrl+b")]
        #expect(throws: ConfigError.self) { try KeymapEditor.hotkeys(from: rows, config: Config()) }
    }

    @Test func savesThroughSymlinkWithoutReplacingIt() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let suffix = UUID().uuidString
        let target = root.appendingPathComponent(".keymap-target-\(suffix).toml")
        let link = root.appendingPathComponent(".keymap-link-\(suffix).toml")
        defer { try? FileManager.default.removeItem(at: target); try? FileManager.default.removeItem(at: link) }
        let source = "[hotkeys]\nclipboard = \"ctrl+alt+a\"\n"
        try source.write(to: target, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        try KeymapEditor.save([KeymapBinding(kind: .clipboard, shortcut: "ctrl+alt+b")], to: link, original: source)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == target.path)
        #expect(try ConfigLoader.parse(String(contentsOf: target, encoding: .utf8)).hotkeys.clipboard == "ctrl+alt+b")
    }

    @Test func escapesTargetsAndRejectsStaleOrInvalidSave() throws {
        let source = "[hotkeys.apps]\n\"ctrl+alt+a\" = \"old\"\n"
        let rows = [KeymapBinding(kind: .app, shortcut: "ctrl+alt+a", target: "A\\B\"C")]
        let updated = try KeymapEditor.updating(source, bindings: rows)
        #expect(try ConfigLoader.parse(updated).hotkeys.apps["ctrl+alt+a"] == "A\\B\"C")

        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".keymap-editor-test-\(UUID().uuidString).toml")
        defer { try? FileManager.default.removeItem(at: url) }
        try source.write(to: url, atomically: true, encoding: .utf8)
        #expect(throws: ConfigError.self) { try KeymapEditor.save(rows, to: url, original: "stale") }
        #expect(try String(contentsOf: url, encoding: .utf8) == source)
        let invalid = [KeymapBinding(kind: .app, shortcut: "not-a-hotkey", target: "App")]
        #expect(throws: ConfigError.self) { try KeymapEditor.save(invalid, to: url, original: source) }
        #expect(try String(contentsOf: url, encoding: .utf8) == source)

        let unsupported = "hotkeys.clipboard = 'ctrl+c'"
        try unsupported.write(to: url, atomically: true, encoding: .utf8)
        #expect(throws: ConfigError.self) { try KeymapEditor.save([], to: url, original: unsupported) }
        #expect(try Data(contentsOf: url) == Data(unsupported.utf8))

        let composed = "# café\n"
        let decomposed = "# cafe\u{301}\n"
        try decomposed.write(to: url, atomically: true, encoding: .utf8)
        #expect(throws: ConfigError.self) { try KeymapEditor.save(rows, to: url, original: composed) }
        #expect(try Data(contentsOf: url) == Data(decomposed.utf8))
    }
}
