import AppKit
import SwiftUI

struct KeyHint: Hashable {
    var keys: String
    var label: String
}

struct PanelChrome<Content: View>: View {
    @Binding var query: String
    var placeholder: String
    var status: String
    var hints: [KeyHint]
    var needsAccessibility: Bool
    var onFieldCreated: (NSTextField) -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                PanelSearchField(text: $query, placeholder: placeholder, onCreated: onFieldCreated)
                    .frame(height: 28)
            }
            .padding(.horizontal, 6)

            if needsAccessibility {
                AccessibilityBanner()
            }

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 14) {
                Text(status)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                ForEach(hints, id: \.self) { hint in
                    HStack(spacing: 5) {
                        Text(hint.keys)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color.primary.opacity(0.08))
                            )
                        Text(hint.label)
                            .foregroundStyle(.secondary)
                    }
                    .fixedSize()
                    .accessibilityElement(children: .combine)
                }
            }
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 6)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Plain AppKit text field so focus, IME composition and field-editor commands
/// behave like any other Mac search box.
struct PanelSearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onCreated: (NSTextField) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 20, weight: .medium)
        field.placeholderString = placeholder
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.delegate = context.coordinator
        field.setAccessibilityLabel(placeholder)
        field.setAccessibilitySubrole(.searchField)
        onCreated(field)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.text = $text
        if field.stringValue != text {
            field.stringValue = text
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            if text.wrappedValue != field.stringValue {
                text.wrappedValue = field.stringValue
            }
        }
    }
}

/// Selected and hovered rows/cells. Uses the system accent so it reads in light,
/// dark, and Increase Contrast; the old white-on-glass fill vanished in light mode.
struct SelectionBackground: View {
    var isSelected: Bool
    var isHovered: Bool = false
    var cornerRadius: CGFloat = 10
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let accent = Color(nsColor: .controlAccentColor)
        shape
            .fill(isSelected ? accent.opacity(0.24) : Color.primary.opacity(isHovered ? 0.07 : 0))
            .overlay(
                shape.strokeBorder(
                    isSelected ? accent.opacity(contrast == .increased ? 1 : 0.65) : Color.clear,
                    lineWidth: contrast == .increased ? 2 : 1
                )
            )
    }
}

struct AccessibilityBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.raised.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("macOS is blocking roto from pasting. Allow roto under Accessibility; until then, press ⌘V yourself.")
                .font(.system(size: 12, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Open Settings") {
                AXSupport.promptIfNeeded()
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.orange.opacity(0.14))
        )
        .accessibilityElement(children: .contain)
    }
}

struct EmptyState: View {
    var symbol: String
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

enum PanelKey {
    static let returnKey: UInt16 = 36
    static let tab: UInt16 = 48
    static let delete: UInt16 = 51
    static let escape: UInt16 = 53
    static let keypadEnter: UInt16 = 76
    static let home: UInt16 = 115
    static let pageUp: UInt16 = 116
    static let forwardDelete: UInt16 = 117
    static let end: UInt16 = 119
    static let pageDown: UInt16 = 121
    static let left: UInt16 = 123
    static let right: UInt16 = 124
    static let down: UInt16 = 125
    static let up: UInt16 = 126

    /// Physical number-row keys 1–9, so ⌘1…⌘9 work on AZERTY too.
    static let digits: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]

    private static let ansiLetters: [UInt16: String] = [
        0: "a", 8: "c", 45: "n", 35: "p", 7: "x", 9: "v", 6: "z", 38: "j", 40: "k",
    ]

    /// Lowercased letter for shortcuts. Falls back to the ANSI key position when a
    /// non-Latin layout (Arabic, Hebrew, Russian, …) reports a non-ASCII character.
    static func letter(_ event: NSEvent) -> String? {
        if let chars = event.charactersIgnoringModifiers?.lowercased(),
           chars.count == 1, let scalar = chars.unicodeScalars.first, scalar.isASCII {
            return chars
        }
        return ansiLetters[event.keyCode]
    }

    static func modifiers(_ event: NSEvent) -> NSEvent.ModifierFlags {
        event.modifierFlags.intersection([.command, .shift, .option, .control])
    }
}

@MainActor
enum PanelFocus {
    /// The field is created during the window's first layout, after `present`
    /// already tried to focus it; focus it once it is in a key window.
    static func focusWhenReady(_ field: NSTextField) {
        DispatchQueue.main.async { [weak field] in
            guard let field, let window = field.window, window.isKeyWindow,
                  field.currentEditor() == nil
            else { return }
            window.makeFirstResponder(field)
        }
    }
}

/// Speaks list selection changes; the VoiceOver cursor stays in the search field.
@MainActor
enum Announcer {
    /// Autoclosed: selection moves on every arrow key, and with VoiceOver off the
    /// announcement is never needed, so it is never built either.
    static func say(_ text: @autoclosure () -> String) {
        guard NSWorkspace.shared.isVoiceOverEnabled, let window = NSApp.keyWindow else { return }
        NSAccessibility.post(
            element: window,
            notification: .announcementRequested,
            userInfo: [
                .announcement: text(),
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }
}

@MainActor
enum AppIcons {
    /// Holds the misses too: a bundle ID with no app on disk would otherwise ask
    /// Launch Services again for every row, on every keystroke.
    private static var cache: [String: NSImage?] = [:]

    static func icon(bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let cached = cache[bundleID] {
            return cached
        }
        let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
        // Subscript assignment of nil would remove the key instead of storing the miss.
        cache.updateValue(icon, forKey: bundleID)
        return icon
    }
}

@MainActor
enum RelativeTime {
    private static let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    static func string(_ date: Date) -> String {
        if Date().timeIntervalSince(date) < 10 {
            return "just now"
        }
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
