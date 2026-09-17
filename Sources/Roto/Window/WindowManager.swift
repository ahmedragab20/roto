import AppKit
import RotoCore

@MainActor
final class WindowManager {
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
        guard let window = AXSupport.focusedWindow(), let axFrame = AXSupport.frame(of: window) else {
            onIssue?("No accessible focused window. Check Accessibility access and try again.")
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
