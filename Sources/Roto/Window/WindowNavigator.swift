import AppKit
import CoreGraphics
import RotoCore

struct OnscreenWindow {
    var pid: pid_t
    var axFrame: CGRect
    var number: Int
}

@MainActor
final class WindowNavigator {
    let screens: ScreenService

    init(screens: ScreenService) {
        self.screens = screens
    }

    func focus(_ direction: Direction) {
        guard let current = currentWindow() else { return }
        let others = listedWindows().filter { $0.number != current.number }
        let primaryMaxY = screens.primaryMaxY
        let origin = Geometry.axToCocoa(current.axFrame, primaryMaxY: primaryMaxY)
        let frames = others.map { Geometry.axToCocoa($0.axFrame, primaryMaxY: primaryMaxY) }
        guard let index = Geometry.nearestIndex(origin: origin, direction: direction, frames: frames) else { return }
        raise(others[index])
    }

    func focusAdjacentDisplay(reverse: Bool) {
        let displays = screens.displays
        guard displays.count > 1 else { return }
        guard let current = currentWindow() else { return }
        let primaryMaxY = displays.first { $0.frame.origin == .zero }?.frame.maxY ?? screens.primaryMaxY
        let cocoa = Geometry.axToCocoa(current.axFrame, primaryMaxY: primaryMaxY)
        let frames = displays.map(\.frame)
        guard let currentIndex = Geometry.displayIndex(containing: cocoa, frames: frames) else { return }
        let next = Geometry.nextIndex(current: currentIndex, count: displays.count, reverse: reverse)
        let candidates = listedWindows().filter { window in
            let c = Geometry.axToCocoa(window.axFrame, primaryMaxY: primaryMaxY)
            return Geometry.displayIndex(containing: c, frames: frames) == next && window.number != current.number
        }
        // CGWindowList is front-to-back; pick the frontmost on that display.
        if let front = candidates.first {
            raise(front)
        }
    }

    private func currentWindow() -> OnscreenWindow? {
        guard let focused = AXSupport.focusedWindow(),
              let axFrame = AXSupport.frame(of: focused),
              let pid = AXSupport.pid(of: focused)
        else { return nil }
        let listed = listedWindows()
        if let match = listed.first(where: { $0.pid == pid && framesClose($0.axFrame, axFrame) }) {
            return match
        }
        return OnscreenWindow(pid: pid, axFrame: axFrame, number: -1)
    }

    private func raise(_ window: OnscreenWindow) {
        let axWindows = AXSupport.windows(of: window.pid)
        if let match = axWindows.first(where: { ax in
            guard let frame = AXSupport.frame(of: ax) else { return false }
            return framesClose(frame, window.axFrame)
        }) {
            WindowFocus.focus(match, pid: window.pid)
            return
        }
        if let app = NSRunningApplication(processIdentifier: window.pid) {
            WindowFocus.activate(app)
        }
    }

    private func listedWindows() -> [OnscreenWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let selfPID = ProcessInfo.processInfo.processIdentifier
        var result: [OnscreenWindow] = []
        for entry in info {
            let layer = entry[kCGWindowLayer as String] as? Int ?? 0
            guard layer == 0 else { continue }
            let pid = entry[kCGWindowOwnerPID as String] as? pid_t ?? 0
            guard pid != 0, pid != selfPID else { continue }
            if let alpha = entry[kCGWindowAlpha as String] as? Double, alpha < 0.05 {
                continue
            }
            guard let bounds = entry[kCGWindowBounds as String] as? [String: Any],
                  let x = bounds["X"] as? CGFloat,
                  let y = bounds["Y"] as? CGFloat,
                  let w = bounds["Width"] as? CGFloat,
                  let h = bounds["Height"] as? CGFloat
            else { continue }
            if w < 40 || h < 40 { continue }
            let number = entry[kCGWindowNumber as String] as? Int ?? 0
            result.append(OnscreenWindow(pid: pid, axFrame: CGRect(x: x, y: y, width: w, height: h), number: number))
        }
        return result
    }

    private func framesClose(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 4 && abs(a.minY - b.minY) < 4
            && abs(a.width - b.width) < 8 && abs(a.height - b.height) < 8
    }
}
