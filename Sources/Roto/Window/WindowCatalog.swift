import AppKit
import ApplicationServices
import RotoCore

/// Private but long-stable HIServices call (used by yabai, AltTab, Rectangle):
/// the CGWindowID behind an AX window, which ties AX windows to the on-screen stack.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

/// AX elements are immutable CF references and may be messaged from any thread.
struct AXWindowRef: @unchecked Sendable {
    let element: AXUIElement
}

struct RunningAppInfo: Sendable {
    let pid: pid_t
    let name: String
    let bundleID: String?
    let isHidden: Bool
    let isFrontmost: Bool
}

struct WindowSnapshot: Sendable {
    var entries: [WindowEntry]
    var elements: [String: AXWindowRef]
}

enum WindowCatalog {
    /// Seconds an unresponsive app may stall a single AX request.
    static let messagingTimeout: Float = 0.3

    @MainActor
    static func runningApps() -> [RunningAppInfo] {
        let selfPID = NSRunningApplication.current.processIdentifier
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != selfPID && !$0.isTerminated }
            .map { app in
                RunningAppInfo(
                    pid: app.processIdentifier,
                    name: app.localizedName ?? app.bundleIdentifier ?? "App",
                    bundleID: app.bundleIdentifier,
                    isHidden: app.isHidden,
                    isFrontmost: app.processIdentifier == front
                )
            }
    }

    /// Every app's windows over Accessibility, read in parallel. Blocks; call off the main thread.
    nonisolated static func snapshot(apps: [RunningAppInfo]) -> WindowSnapshot {
        let stack = onScreenStack()
        let rows = Rows(count: apps.count)
        DispatchQueue.concurrentPerform(iterations: apps.count) { index in
            rows.set(index, windows(of: apps[index], stack: stack))
        }
        var snapshot = WindowSnapshot(entries: [], elements: [:])
        for (index, app) in apps.enumerated() {
            let found = rows.get(index)
            if found.isEmpty {
                snapshot.entries.append(WindowEntry(
                    id: "app-\(app.pid)",
                    pid: app.pid,
                    appName: app.name,
                    bundleID: app.bundleID,
                    isAppHidden: app.isHidden,
                    isAppOnly: true
                ))
            }
            for (entry, ref) in found {
                snapshot.entries.append(entry)
                snapshot.elements[entry.id] = ref
            }
        }
        return snapshot
    }

    /// Standard windows of one app, front to back.
    nonisolated static func windows(of app: RunningAppInfo) -> [(entry: WindowEntry, ref: AXWindowRef)] {
        windows(of: app, stack: onScreenStack())
            .sorted { ($0.entry.stackOrder ?? Int.max) < ($1.entry.stackOrder ?? Int.max) }
    }

    nonisolated private static func windows(
        of app: RunningAppInfo,
        stack: [CGWindowID: Int]
    ) -> [(entry: WindowEntry, ref: AXWindowRef)] {
        let appElement = AXUIElementCreateApplication(app.pid)
        AXUIElementSetMessagingTimeout(appElement, messagingTimeout)
        guard let windows = AXSupport.copy(appElement, kAXWindowsAttribute as String) as? [AXUIElement] else {
            return []
        }
        var focusedID: CGWindowID?
        if app.isFrontmost, let focused = AXSupport.copy(appElement, kAXFocusedWindowAttribute as String) {
            focusedID = windowID(of: focused as! AXUIElement)
        }

        let attributes = [
            kAXSubroleAttribute, kAXTitleAttribute, kAXMinimizedAttribute,
            kAXPositionAttribute, kAXSizeAttribute, "AXFullScreen",
        ] as CFArray

        var result: [(entry: WindowEntry, ref: AXWindowRef)] = []
        for (index, window) in windows.enumerated() {
            AXUIElementSetMessagingTimeout(window, messagingTimeout)
            var values: CFArray?
            guard AXUIElementCopyMultipleAttributeValues(window, attributes, [], &values) == .success,
                  let list = values as? [AnyObject], list.count == 6
            else { continue }
            let subrole = list[0] as? String
            guard subrole == kAXStandardWindowSubrole as String || subrole == kAXDialogSubrole as String else {
                continue
            }
            let id = windowID(of: window)
            var frame: CGRect?
            if let origin = point(list[3]), let size = size(list[4]) {
                frame = CGRect(origin: origin, size: size)
            }
            let entry = WindowEntry(
                id: id.map { "window-\($0)" } ?? "window-\(app.pid)-\(index)",
                pid: app.pid,
                appName: app.name,
                bundleID: app.bundleID,
                title: (list[1] as? String) ?? "",
                windowID: id,
                frame: frame,
                isMinimized: (list[2] as? Bool) ?? false,
                isAppHidden: app.isHidden,
                isFullScreen: (list[5] as? Bool) ?? false,
                isFocused: id != nil && id == focusedID,
                stackOrder: id.flatMap { stack[$0] }
            )
            result.append((entry, AXWindowRef(element: window)))
        }
        return result
    }

    nonisolated static func windowID(of element: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(element, &id) == .success && id != 0 ? id : nil
    }

    /// Front-to-back rank of normal-layer windows on the current Space.
    nonisolated private static func onScreenStack() -> [CGWindowID: Int] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return [:]
        }
        var order: [CGWindowID: Int] = [:]
        for entry in info where (entry[kCGWindowLayer as String] as? Int ?? 0) == 0 {
            if let number = entry[kCGWindowNumber as String] as? Int {
                order[CGWindowID(number)] = order.count
            }
        }
        return order
    }

    nonisolated private static func point(_ value: AnyObject) -> CGPoint? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
    }

    nonisolated private static func size(_ value: AnyObject) -> CGSize? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &size) ? size : nil
    }

    private final class Rows: @unchecked Sendable {
        private let lock = NSLock()
        private var rows: [[(entry: WindowEntry, ref: AXWindowRef)]]

        init(count: Int) {
            rows = Array(repeating: [], count: count)
        }

        func set(_ index: Int, _ value: [(entry: WindowEntry, ref: AXWindowRef)]) {
            lock.lock()
            rows[index] = value
            lock.unlock()
        }

        func get(_ index: Int) -> [(entry: WindowEntry, ref: AXWindowRef)] {
            lock.lock()
            defer { lock.unlock() }
            return rows[index]
        }
    }
}
