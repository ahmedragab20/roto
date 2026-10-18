import Foundation
import Testing
@testable import RotoCore

struct SystemShortcutsTests {
    private let commandSpace = try! KeyCombo.parse("cmd+space")

    private func entry(enabled: Bool, keyCode: Int = 49, modifiers: Int = 1 << 20) -> [String: Any] {
        [
            "enabled": NSNumber(value: enabled),
            "value": ["parameters": [NSNumber(value: 65535), NSNumber(value: keyCode), NSNumber(value: modifiers)]],
        ]
    }

    @Test func untouchedSpotlightOwnsCommandSpace() {
        #expect(SystemShortcuts.spotlightConflict(with: commandSpace, table: nil)?.id == 64)
        #expect(SystemShortcuts.spotlightConflict(with: commandSpace, table: [:])?.id == 64)
    }

    @Test func turnedOffSpotlightFreesTheKey() {
        let table: [String: Any] = ["64": entry(enabled: false)]
        #expect(SystemShortcuts.spotlightConflict(with: commandSpace, table: table) == nil)
    }

    @Test func followsARemappedSpotlightKey() throws {
        // Spotlight moved to ⌃Space.
        let table: [String: Any] = ["64": entry(enabled: true, modifiers: 1 << 18)]
        #expect(SystemShortcuts.spotlightConflict(with: commandSpace, table: table) == nil)
        let controlSpace = try KeyCombo.parse("ctrl+space")
        #expect(SystemShortcuts.spotlightConflict(with: controlSpace, table: table)?.id == 64)
    }

    @Test func findersSearchWindowKeyAlsoConflicts() throws {
        let optionCommandSpace = try KeyCombo.parse("alt+cmd+space")
        #expect(SystemShortcuts.spotlightConflict(with: optionCommandSpace, table: nil)?.id == 65)
        #expect(SystemShortcuts.spotlightConflict(with: try KeyCombo.parse("ctrl+alt+space"), table: nil) == nil)
    }
}
