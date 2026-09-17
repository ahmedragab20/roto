import Foundation
import Testing
@testable import RotoCore

struct KeyComboTests {
    @Test func parsesModifiersAndArrow() throws {
        let combo = try KeyCombo.parse("ctrl+alt+left")
        #expect(combo.keyName == "left")
        #expect(combo.keyCode == 0x7B)
        #expect(combo.carbonModifiers & KeyCombo.controlBit != 0)
        #expect(combo.carbonModifiers & KeyCombo.optionBit != 0)
        #expect(combo.canonical == "ctrl+alt+left")
    }

    @Test func canonicalizesAliases() throws {
        let combo = try KeyCombo.parse("control+option+cmd+Shift+Period")
        #expect(combo.keyName == "period")
        #expect(combo.canonical == "ctrl+alt+shift+cmd+period")
        #expect(combo.carbonModifiers & KeyCombo.cmdBit != 0)
        #expect(combo.carbonModifiers & KeyCombo.shiftBit != 0)
    }

    @Test func rejectsUnknownKey() {
        #expect(throws: ConfigError.self) {
            try KeyCombo.parse("ctrl+alt+notakey")
        }
    }

    @Test func rejectsMissingModifier() {
        #expect(throws: ConfigError.self) {
            try KeyCombo.parse("a")
        }
    }

    @Test func rejectsTwoKeys() {
        #expect(throws: ConfigError.self) {
            try KeyCombo.parse("ctrl+a+b")
        }
    }
}
