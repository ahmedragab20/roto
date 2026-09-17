import Foundation
import Testing
@testable import RotoCore

struct CheatsheetTests {
    @Test func displayKeysUseMenuOrder() throws {
        #expect(Cheatsheet.displayKeys(try KeyCombo.parse("cmd+shift+alt+ctrl+left")) == "⌃⌥⇧⌘←")
        #expect(Cheatsheet.displayKeys(try KeyCombo.parse("ctrl+alt+b")) == "⌃⌥B")
        #expect(Cheatsheet.displayKeys(try KeyCombo.parse("ctrl+alt+slash")) == "⌃⌥/")
        #expect(Cheatsheet.displayKeys(try KeyCombo.parse("ctrl+alt+enter")) == "⌃⌥↩")
        #expect(Cheatsheet.displayKeys(try KeyCombo.parse("alt+f5")) == "⌥F5")
        #expect(Cheatsheet.displayKeys(try KeyCombo.parse("ctrl+numpad1")) == "⌃Num 1")
    }

    @Test func sectionsFollowConfig() throws {
        let toml = """
            [hotkeys.window]
            "ctrl+alt+right" = "half-right"
            "ctrl+alt+left" = "half-left"
            "ctrl+alt+shift+h" = "focus-left"
            "ctrl+alt+cmd+right" = "next-display"
            [hotkeys.apps]
            "ctrl+alt+t" = "com.mitchellh.ghostty"
            [hotkeys]
            clipboard = "ctrl+alt+v"
            """
        let config = try ConfigLoader.parse(toml)
        let sections = Cheatsheet.sections(for: config)
        #expect(sections.map(\.title) == [
            "Popups", "Apps", "Window layout", "Displays", "Window focus",
            "In clipboard history", "In emoji picker", "In window switcher", "In this sheet",
        ])
        #expect(sections[0].entries.map(\.title) == ["Clipboard history"])
        #expect(sections[1].entries.first?.appTarget == "com.mitchellh.ghostty")
        #expect(sections[1].entries.first?.keys == "⌃⌥T")
        #expect(sections[2].entries.map(\.title) == ["Left half", "Right half"])
        #expect(sections[3].entries.map(\.title) == ["Move window to next display"])
        #expect(sections[4].entries.map(\.title) == ["Focus window to the left"])
    }

    @Test func emptySectionsAreDropped() {
        let sections = Cheatsheet.sections(for: Config())
        #expect(sections.map(\.title) == [
            "In clipboard history", "In emoji picker", "In window switcher", "In this sheet",
        ])
    }

    @Test func describesWindowActions() {
        #expect(Cheatsheet.describe(windowAction: "layout:editor") == "Layout “editor”")
        #expect(Cheatsheet.describe(windowAction: "maximize") == "Maximize")
        #expect(Cheatsheet.describe(windowAction: "weird") == "weird")
    }
}
