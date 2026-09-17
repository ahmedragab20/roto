import CoreGraphics
import Foundation

public enum Direction: String, Sendable, Equatable, CaseIterable {
    case left
    case right
    case up
    case down
}

public enum WindowCommand: Sendable, Equatable {
    case apply(FractionalRect)
    case center
    case centerLarge
    case nextDisplay
    case prevDisplay
    case focus(Direction)
    case focusNextDisplay
    case focusPrevDisplay
}

public enum BoundAction: Sendable, Equatable {
    case window(WindowCommand)
    case app(String)
    case clipboard
    case emoji
    case windows
    case cheatsheet
}

public struct Layout {
    public static let presets: [String: FractionalRect] = [
        "half-left": FractionalRect(x: 0, y: 0, w: 0.5, h: 1),
        "half-right": FractionalRect(x: 0.5, y: 0, w: 0.5, h: 1),
        "half-top": FractionalRect(x: 0, y: 0.5, w: 1, h: 0.5),
        "half-bottom": FractionalRect(x: 0, y: 0, w: 1, h: 0.5),
        "quarter-top-left": FractionalRect(x: 0, y: 0.5, w: 0.5, h: 0.5),
        "quarter-top-right": FractionalRect(x: 0.5, y: 0.5, w: 0.5, h: 0.5),
        "quarter-bottom-left": FractionalRect(x: 0, y: 0, w: 0.5, h: 0.5),
        "quarter-bottom-right": FractionalRect(x: 0.5, y: 0, w: 0.5, h: 0.5),
        "third-left": FractionalRect(x: 0, y: 0, w: 1.0 / 3.0, h: 1),
        "third-center": FractionalRect(x: 1.0 / 3.0, y: 0, w: 1.0 / 3.0, h: 1),
        "third-right": FractionalRect(x: 2.0 / 3.0, y: 0, w: 1.0 / 3.0, h: 1),
        "two-thirds-left": FractionalRect(x: 0, y: 0, w: 2.0 / 3.0, h: 1),
        "two-thirds-right": FractionalRect(x: 1.0 / 3.0, y: 0, w: 2.0 / 3.0, h: 1),
        "maximize": FractionalRect(x: 0, y: 0, w: 1, h: 1),
        "almost-maximize": FractionalRect(x: 0.05, y: 0.05, w: 0.90, h: 0.90),
    ]

    public static func preset(_ name: String) -> FractionalRect? {
        presets[name]
    }

    /// Cocoa (y-up) visible frame → destination rect, with a uniform gap.
    public static func apply(_ fraction: FractionalRect, in visible: CGRect, gap: CGFloat) -> CGRect {
        let g = max(gap, 0)
        let x = visible.minX + CGFloat(fraction.x) * visible.width + g
        let y = visible.minY + CGFloat(fraction.y) * visible.height + g
        let w = CGFloat(fraction.w) * visible.width - 2 * g
        let h = CGFloat(fraction.h) * visible.height - 2 * g
        return CGRect(x: x, y: y, width: max(w, 1), height: max(h, 1))
    }

    /// A large, centered frame that still shows the desktop around it. Width is
    /// capped relative to height so ultrawide displays keep a comfortable shape.
    public static func centeredLarge(in visible: CGRect) -> CGRect {
        let height = (visible.height * 0.86).rounded()
        let width = min(visible.width * 0.8, height * 1.6).rounded()
        return CGRect(
            x: (visible.midX - width / 2).rounded(),
            y: (visible.midY - height / 2).rounded(),
            width: width,
            height: height
        )
    }

    public static func resolveWindowCommand(
        _ action: String,
        layouts: [String: FractionalRect]
    ) throws -> WindowCommand {
        let name = action.trimmingCharacters(in: .whitespacesAndNewlines)
        if name == "center" { return .center }
        if name == "center-large" { return .centerLarge }
        if name == "next-display" { return .nextDisplay }
        if name == "prev-display" { return .prevDisplay }
        if name == "focus-next-display" { return .focusNextDisplay }
        if name == "focus-prev-display" { return .focusPrevDisplay }
        if name.hasPrefix("focus-") {
            let dir = String(name.dropFirst("focus-".count))
            guard let direction = Direction(rawValue: dir) else {
                throw ConfigError.validation("unknown window action '\(action)'")
            }
            return .focus(direction)
        }
        if name.hasPrefix("layout:") {
            let key = String(name.dropFirst("layout:".count))
            guard let rect = layouts[key] else {
                throw ConfigError.validation("unknown layout '\(key)'")
            }
            return .apply(rect)
        }
        if let rect = preset(name) {
            return .apply(rect)
        }
        throw ConfigError.validation("unknown window action '\(action)'")
    }
}
