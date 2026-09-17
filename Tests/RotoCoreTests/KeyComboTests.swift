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

    @Test func recordsPhysicalKeysWithStableTokens() throws {
        let combo = try KeyCombo.recorded(
            keyCode: 0x24,
            carbonModifiers: KeyCombo.cmdBit | KeyCombo.controlBit | KeyCombo.shiftBit | KeyCombo.optionBit
        )
        #expect(combo.canonical == "ctrl+alt+shift+cmd+enter")
        #expect(try KeyCombo.recorded(keyCode: 0x2F, carbonModifiers: KeyCombo.optionBit).canonical == "alt+period")
        #expect(try KeyCombo.recorded(keyCode: 0x33, carbonModifiers: KeyCombo.cmdBit).keyName == "delete")
        #expect(try KeyCombo.recorded(keyCode: 0x35, carbonModifiers: KeyCombo.controlBit).keyName == "escape")
    }

    @Test func everySupportedPhysicalKeyCanBeRecorded() throws {
        for code in Set(KeyCodes.names.values) {
            let recorded = try KeyCombo.recorded(keyCode: code, carbonModifiers: KeyCombo.controlBit)
            #expect(recorded.keyCode == code)
            #expect(recorded.carbonModifiers == KeyCombo.controlBit)
        }
    }

    @Test func rejectsUnsupportedRecording() {
        #expect(throws: ConfigError.self) { try KeyCombo.recorded(keyCode: 0xFFFF, carbonModifiers: KeyCombo.cmdBit) }
        #expect(throws: ConfigError.self) { try KeyCombo.recorded(keyCode: 0, carbonModifiers: 0) }
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
