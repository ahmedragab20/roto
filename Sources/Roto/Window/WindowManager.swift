import AppKit
import RotoCore

@MainActor
final class WindowManager {
    let screens: ScreenService
    var gap: CGFloat = 0

    init(screens: ScreenService) {
        self.screens = screens
    }

    func perform(_ command: WindowCommand) {
        switch command {
        case .apply(let fraction):
            apply(fraction)
        case .center:
            center()
        case .nextDisplay:
            moveToAdjacentDisplay(reverse: false)
        case .prevDisplay:
            moveToAdjacentDisplay(reverse: true)
        case .focus, .focusNextDisplay, .focusPrevDisplay:
            break
        }
    }

    private func apply(_ fraction: FractionalRect) {
        guard let window = AXSupport.focusedWindow(),
              let axFrame = AXSupport.frame(of: window)
        else { return }
        let cocoa = Geometry.axToCocoa(axFrame, primaryMaxY: screens.primaryMaxY)
        guard let visible = visibleFrame(containing: cocoa) else { return }
        let destCocoa = Layout.apply(fraction, in: visible, gap: gap)
        AXSupport.setFrame(window, Geometry.cocoaToAX(destCocoa, primaryMaxY: screens.primaryMaxY))
    }

    private func center() {
        guard let window = AXSupport.focusedWindow(),
              let axFrame = AXSupport.frame(of: window)
        else { return }
        let cocoa = Geometry.axToCocoa(axFrame, primaryMaxY: screens.primaryMaxY)
        guard let visible = visibleFrame(containing: cocoa) else { return }
        let dest = Geometry.centered(size: cocoa.size, in: visible)
        AXSupport.setFrame(window, Geometry.cocoaToAX(dest, primaryMaxY: screens.primaryMaxY))
    }

    private func moveToAdjacentDisplay(reverse: Bool) {
        guard let window = AXSupport.focusedWindow(),
              let axFrame = AXSupport.frame(of: window)
        else { return }
        let displays = screens.displays
        guard !displays.isEmpty else { return }
        let cocoa = Geometry.axToCocoa(axFrame, primaryMaxY: screens.primaryMaxY)
        let frames = displays.map(\.visibleFrame)
        let current = Geometry.displayIndex(containing: cocoa, frames: frames) ?? 0
        let next = Geometry.nextIndex(current: current, count: displays.count, reverse: reverse)
        let dest = Geometry.mapRect(cocoa, from: displays[current].visibleFrame, to: displays[next].visibleFrame)
        AXSupport.setFrame(window, Geometry.cocoaToAX(dest, primaryMaxY: screens.primaryMaxY))
    }

    private func visibleFrame(containing rect: CGRect) -> CGRect? {
        let frames = screens.displays.map(\.visibleFrame)
        guard let index = Geometry.displayIndex(containing: rect, frames: frames) else {
            return screens.displays.first?.visibleFrame
        }
        return frames[index]
    }
}
