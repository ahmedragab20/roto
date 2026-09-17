import AppKit
import ApplicationServices
import os

@MainActor
enum WindowFocus {
    nonisolated static let log = Logger(subsystem: "dev.roto.app", category: "focus")
    private static let requests = FocusRequests()

    /// A newer non-focus command (for example, hide or opening a popup) also retires old work.
    static func cancelPending() {
        _ = requests.begin()
    }

    /// Brings an app to the front. macOS 14+ may ignore activation requests from a
    /// background app, so this checks the result and falls back to Launch Services,
    /// which always honors it (the same path as clicking the Dock icon).
    static func activate(_ app: NSRunningApplication) {
        activate(app, request: requests.begin())
    }

    private static func activate(_ app: NSRunningApplication, request: UInt64) {
        if app.isHidden {
            app.unhide()
        }
        if NSApp.isActive {
            NSApp.yieldActivation(to: app)
        }
        app.activate()
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(element, kAXFrontmostAttribute as CFString, kCFBooleanTrue)

        let pid = app.processIdentifier
        requests.after(0.3, request: request) {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier != pid,
                  let running = NSRunningApplication(processIdentifier: pid),
                  let url = running.bundleURL
            else { return }
            log.notice("activation of \(running.bundleIdentifier ?? "?", privacy: .public) ignored; using Launch Services")
            open(url)
        }
    }

    /// Opens or re-opens an app like its Dock icon: launches it, restores a
    /// minimized window, or asks it for a new window when it has none.
    static func open(_ url: URL) {
        _ = requests.begin()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error {
                log.error("could not open \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Focuses one specific window: restores it, makes it the app's main window,
    /// raises it, then activates the app.
    static func focus(_ window: AXUIElement, pid: pid_t) {
        let request = requests.begin()
        AXUIElementSetMessagingTimeout(window, 0.5)
        if boolValue(window, kAXMinimizedAttribute) == true {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        if let app = NSRunningApplication(processIdentifier: pid) {
            activate(app, request: request)
        }
        // Activation can put the app's previous key window back on top; raise again.
        let ref = AXWindowRef(element: window)
        requests.after(0.08, request: request) {
            AXUIElementPerformAction(ref.element, kAXRaiseAction as CFString)
        }
    }

    @discardableResult
    static func close(_ window: AXUIElement) -> Bool {
        guard let button = AXSupport.copy(window, kAXCloseButtonAttribute as String) else { return false }
        return AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString) == .success
    }

    @discardableResult
    static func toggleMinimized(_ window: AXUIElement) -> Bool {
        let minimized = boolValue(window, kAXMinimizedAttribute) ?? false
        let value: CFBoolean = minimized ? kCFBooleanFalse : kCFBooleanTrue
        return AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, value) == .success
    }

    private static func boolValue(_ element: AXUIElement, _ attribute: String) -> Bool? {
        AXSupport.copy(element, attribute) as? Bool
    }
}
