import AppKit
import os
import RotoCore

@MainActor
final class WindowManager {
    private let log = Logger(subsystem: "dev.roto.app", category: "window")
    let screens: ScreenService
    var gap: CGFloat = 0
    var onIssue: ((String?) -> Void)?

    init(screens: ScreenService) {
        self.screens = screens
    }

    func perform(_ command: WindowCommand) {
        switch command {
        case .focus, .focusNextDisplay, .focusPrevDisplay:
            return // Routed to WindowNavigator by AppDelegate.
        default:
            break
        }
        // Only blame the permission when it is actually missing. Saying "check
        // Accessibility access" while the menu reads "Accessibility: granted"
        // sends people to a setting that is already correct.
        guard AXSupport.isTrusted else {
            onIssue?("Accessibility access is off, so roto cannot move windows. Turn it on in System Settings.")
            return
        }
        let found = AXSupport.focusedWindowResult()
        guard let window = found.window else {
            log.notice("window command found no target: \(found.reason, privacy: .public)")
            onIssue?(found.reason)
            return
        }
        guard let axFrame = AXSupport.frame(of: window) else {
            onIssue?("Could not read the focused window's position. The app may be busy; try again.")
            return
        }
        let displays = screens.displays
        // Use a single display snapshot for source selection, mapping, and AX conversion.
        let primaryMaxY = displays.first { $0.frame.origin == .zero }?.frame.maxY ?? screens.primaryMaxY
        let cocoa = Geometry.axToCocoa(axFrame, primaryMaxY: primaryMaxY)
        guard let current = Geometry.displayIndex(containing: cocoa, frames: displays.map(\.frame)) else {
            onIssue?("No display is available for this window.")
            return
        }
        var bounds = displays[current].visibleFrame
        let destination: CGRect
        switch command {
        case .apply(let fraction):
            destination = Layout.apply(fraction, in: bounds, gap: gap)
        case .center:
            destination = Geometry.centered(size: cocoa.size, in: bounds)
        case .centerLarge:
            destination = Layout.centeredLarge(in: bounds)
        case .nextDisplay, .prevDisplay:
            guard displays.count > 1 else {
                onIssue?("Connect another display to move this window between screens.")
                return
            }
            let next = Geometry.nextIndex(current: current, count: displays.count, reverse: command == .prevDisplay)
            bounds = displays[next].visibleFrame
            destination = Geometry.mapRect(cocoa, from: displays[current].visibleFrame, to: bounds)
        case .focus, .focusNextDisplay, .focusPrevDisplay:
            return
        }
        let issue = AXSupport.setFrame(
            window,
            Geometry.cocoaToAX(destination, primaryMaxY: primaryMaxY),
            bounds: Geometry.cocoaToAX(bounds, primaryMaxY: primaryMaxY)
        )
        onIssue?(issue)
    }
}
