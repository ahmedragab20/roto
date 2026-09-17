import AppKit
import Carbon
import CoreGraphics
import os

@MainActor
enum Paster {
    static let log = Logger(subsystem: "dev.roto.app", category: "insert")

    /// Posts ⌘V to the frontmost app, using whichever key types "v" in the
    /// current layout (Dvorak, AZERTY, …) instead of assuming ANSI.
    static func pasteCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        // Keep keys the user is still holding from leaking into the synthetic chord.
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )
        let key = KeyboardLayout.keyCode(for: "v") ?? CGKeyCode(kVK_ANSI_V)
        logTarget("paste ⌘V key=\(key)")
        // 0x08 marks the left ⌘ key; some apps only accept device-dependent flags.
        let flags = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x08)
        for keyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: keyDown) else { return }
            event.flags = flags
            event.post(tap: .cgAnnotatedSessionEventTap)
        }
    }

    /// Types text directly, without touching the clipboard.
    static func typeUnicode(_ string: String) {
        logTarget("type \(string.utf16.count) UTF-16 units")
        let source = CGEventSource(stateID: .combinedSessionState)
        for chunk in chunks(of: string) {
            let utf16 = Array(chunk.utf16)
            for keyDown in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: keyDown) else { return }
                // Clear modifiers so a held key cannot turn the glyph into a shortcut.
                event.flags = []
                event.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
                event.post(tap: .cgAnnotatedSessionEventTap)
            }
        }
    }

    /// Records where a synthetic event is about to go; never the content itself.
    private static func logTarget(_ action: String) {
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none"
        log.notice("""
            \(action, privacy: .public) front=\(front, privacy: .public) \
            ax=\(AXIsProcessTrusted(), privacy: .public) post=\(CGPreflightPostEventAccess(), privacy: .public) \
            rotoActive=\(NSApp.isActive, privacy: .public) rotoKeyWindow=\(NSApp.keyWindow != nil, privacy: .public)
            """)
    }

    /// Whole characters, at most 20 UTF-16 units per event (apps drop the rest).
    private static func chunks(of string: String) -> [String] {
        var chunks: [String] = []
        var current = ""
        for character in string {
            if !current.isEmpty, current.utf16.count + character.utf16.count > 20 {
                chunks.append(current)
                current = ""
            }
            current.append(character)
        }
        if !current.isEmpty {
            chunks.append(current)
        }
        return chunks
    }
}

@MainActor
enum KeyboardLayout {
    /// Virtual key that produces `character` with ⌘ held, or nil if no key does.
    static func keyCode(for character: Character) -> CGKeyCode? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        let target = Array(String(character).utf16)
        let commandState = UInt32((cmdKey >> 8) & 0xFF)

        return layoutData.withUnsafeBytes { raw -> CGKeyCode? in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var chars = [UniChar](repeating: 0, count: 4)
            for code in 0..<128 {
                var deadKeys: UInt32 = 0
                var length = 0
                let status = UCKeyTranslate(
                    layout,
                    UInt16(code),
                    UInt16(kUCKeyActionDown),
                    commandState,
                    UInt32(LMGetKbdType()),
                    OptionBits(kUCKeyTranslateNoDeadKeysBit),
                    &deadKeys,
                    chars.count,
                    &length,
                    &chars
                )
                if status == noErr, length == target.count, Array(chars.prefix(length)) == target {
                    return CGKeyCode(code)
                }
            }
            return nil
        }
    }
}
