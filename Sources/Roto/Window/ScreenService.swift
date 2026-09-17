import AppKit
import ApplicationServices
import RotoCore

@MainActor
final class ScreenService {
    struct Display: Equatable {
        var frame: CGRect
        var visibleFrame: CGRect
    }

    /// Cocoa y of the top of the primary display (origin at (0,0)).
    var primaryMaxY: CGFloat {
        let screens = NSScreen.screens
        if let primary = screens.first(where: { $0.frame.origin == .zero }) {
            return primary.frame.maxY
        }
        return screens.first?.frame.maxY ?? 0
    }

    /// Displays sorted left-to-right, then bottom-to-top, in Cocoa coordinates.
    var displays: [Display] {
        let screens = NSScreen.screens.map {
            Display(frame: $0.frame, visibleFrame: $0.visibleFrame)
        }
        let order = Geometry.sortDisplayOrder(screens.map(\.frame))
        return order.map { screens[$0] }
    }

    static func panelOrigin(size: NSSize, screen: PopupScreen) -> NSPoint {
        let chosen: NSScreen?
        switch screen {
        case .primary:
            chosen = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens.first
        case .cursor:
            let loc = NSEvent.mouseLocation
            chosen = NSScreen.screens.first { NSMouseInRect(loc, $0.frame, false) }
                ?? NSScreen.screens.first
        case .frontmost:
            chosen = NSScreen.main ?? NSScreen.screens.first
        }
        let visible = chosen?.visibleFrame ?? .zero
        return NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2 + 60
        )
    }
}

/// A read-back-verified frame write, with an injectable AX boundary for native unit tests.
struct WindowFrameWriter {
    var setPosition: (CGPoint) -> AXError
    var setSize: (CGSize) -> AXError
    var readFrame: () -> CGRect?

    func apply(_ requested: CGRect, bounds: CGRect? = nil) -> String? {
        let initialMove = setPosition(requested.origin)
        let resize = setSize(requested.size)
        // Apps can enforce a minimum size or reject resizing. Position that actual size,
        // not the requested one, so a small destination display keeps the titlebar reachable.
        let size = readFrame()?.size ?? requested.size
        var origin = requested.origin
        if let bounds {
            origin.x = min(max(origin.x, bounds.minX), max(bounds.minX, bounds.maxX - size.width))
            origin.y = min(max(origin.y, bounds.minY), max(bounds.minY, bounds.maxY - size.height))
        }
        let finalMove = setPosition(origin)
        guard let actual = readFrame() else {
            return "Could not verify the window frame. Check Accessibility access and try again."
        }
        if abs(actual.minX - origin.x) > 1 || abs(actual.minY - origin.y) > 1 {
            let failure = [finalMove, initialMove].first { $0 != .success }
            let detail = failure.map { " (AX \($0.rawValue))" } ?? ""
            return "Window position was not applied\(detail). The app may restrict movement."
        }
        if abs(actual.width - requested.width) > 1 || abs(actual.height - requested.height) > 1 {
            let detail = resize == .success ? "" : " (AX \(resize.rawValue))"
            return "The app did not accept the requested window size\(detail)."
        }
        if let bounds, actual.width > bounds.width + 1 || actual.height > bounds.height + 1 {
            return "The window is larger than this display; its top-left corner was kept reachable."
        }
        return nil
    }
}

enum AXSupport {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Synthetic ⌘V / typing needs the post-event permission, which follows the
    /// Accessibility switch; check both so one stale answer cannot block pasting.
    static var canPostEvents: Bool {
        CGPreflightPostEventAccess() || AXIsProcessTrusted()
    }

    @discardableResult
    static func promptIfNeeded() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value
    }

    static func focusedWindow() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        guard let appRef = copy(system, kAXFocusedApplicationAttribute as String) else { return nil }
        let app = appRef as! AXUIElement
        guard let windowRef = copy(app, kAXFocusedWindowAttribute as String) else { return nil }
        return (windowRef as! AXUIElement)
    }

    static func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        guard let ref = copy(system, kAXFocusedUIElementAttribute as String) else { return nil }
        return (ref as! AXUIElement)
    }

    static func focus(_ element: AXUIElement) {
        if let windowRef = copy(element, kAXWindowAttribute as String) {
            AXUIElementPerformAction(windowRef as! AXUIElement, kAXRaiseAction as CFString)
        }
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }

    static func pid(of element: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        let result = AXUIElementGetPid(element, &pid)
        return result == .success ? pid : nil
    }

    static func point(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        guard let value = copy(element, attribute) else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    static func size(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        guard let value = copy(element, attribute) else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(value as! AXValue, .cgSize, &size) else { return nil }
        return size
    }

    @discardableResult
    static func setPoint(_ element: AXUIElement, _ attribute: String, _ point: CGPoint) -> AXError {
        var value = point
        guard let ax = AXValueCreate(.cgPoint, &value) else { return .illegalArgument }
        return AXUIElementSetAttributeValue(element, attribute as CFString, ax)
    }

    @discardableResult
    static func setSize(_ element: AXUIElement, _ attribute: String, _ size: CGSize) -> AXError {
        var value = size
        guard let ax = AXValueCreate(.cgSize, &value) else { return .illegalArgument }
        return AXUIElementSetAttributeValue(element, attribute as CFString, ax)
    }

    static func frame(of window: AXUIElement) -> CGRect? {
        guard let origin = point(window, kAXPositionAttribute as String),
              let size = size(window, kAXSizeAttribute as String)
        else { return nil }
        return CGRect(origin: origin, size: size)
    }

    @discardableResult
    static func setFrame(_ window: AXUIElement, _ axFrame: CGRect, bounds: CGRect? = nil) -> String? {
        WindowFrameWriter(
            setPosition: { setPoint(window, kAXPositionAttribute as String, $0) },
            setSize: { setSize(window, kAXSizeAttribute as String, $0) },
            readFrame: { frame(of: window) }
        ).apply(axFrame, bounds: bounds)
    }

    static func windows(of pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        guard let ref = copy(app, kAXWindowsAttribute as String) else { return [] }
        return (ref as? [AXUIElement]) ?? []
    }

}
