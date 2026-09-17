import Foundation
import Testing
@testable import RotoCore

struct LayoutTests {
    @Test func presetsCoverPlanNames() {
        for name in [
            "half-left", "half-right", "half-top", "half-bottom",
            "quarter-top-left", "quarter-top-right", "quarter-bottom-left", "quarter-bottom-right",
            "third-left", "third-center", "third-right",
            "two-thirds-left", "two-thirds-right",
            "maximize", "almost-maximize",
        ] {
            #expect(Layout.preset(name) != nil, "missing preset \(name)")
        }
    }

    @Test func applyRespectsGapAndFractions() {
        let visible = CGRect(x: 100, y: 50, width: 1000, height: 800)
        let rect = Layout.apply(FractionalRect(x: 0, y: 0, w: 0.5, h: 1), in: visible, gap: 10)
        #expect(rect.origin.x == 110)
        #expect(rect.origin.y == 60)
        #expect(rect.width == 480)
        #expect(rect.height == 780)
    }

    @Test func resolveCustomLayout() throws {
        let layouts = ["editor": FractionalRect(x: 0, y: 0, w: 0.6, h: 1)]
        let command = try Layout.resolveWindowCommand("layout:editor", layouts: layouts)
        #expect(command == .apply(FractionalRect(x: 0, y: 0, w: 0.6, h: 1)))
    }

    @Test func resolveFocusAndCenter() throws {
        #expect(try Layout.resolveWindowCommand("center", layouts: [:]) == .center)
        #expect(try Layout.resolveWindowCommand("focus-left", layouts: [:]) == .focus(.left))
        #expect(try Layout.resolveWindowCommand("next-display", layouts: [:]) == .nextDisplay)
        #expect(try Layout.resolveWindowCommand("focus-next-display", layouts: [:]) == .focusNextDisplay)
    }
}

struct GeometryTests {
    @Test func cocoaAXRoundTrip() {
        let primary: CGFloat = 1080
        let cocoa = CGRect(x: 100, y: 200, width: 300, height: 150)
        let ax = Geometry.cocoaToAX(cocoa, primaryMaxY: primary)
        #expect(ax.origin.y == CGFloat(1080 - 200 - 150))
        let back = Geometry.axToCocoa(ax, primaryMaxY: primary)
        #expect(back == cocoa)
    }

    @Test func picksDisplayByCenter() {
        let left = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let right = CGRect(x: 1000, y: 0, width: 1200, height: 800)
        #expect(Geometry.displayIndex(containing: CGRect(x: 100, y: 10, width: 50, height: 50), frames: [left, right]) == 0)
        #expect(Geometry.displayIndex(containing: CGRect(x: 1500, y: 10, width: 50, height: 50), frames: [left, right]) == 1)
    }

    @Test func nextIndexWraps() {
        #expect(Geometry.nextIndex(current: 0, count: 2, reverse: false) == 1)
        #expect(Geometry.nextIndex(current: 1, count: 2, reverse: false) == 0)
        #expect(Geometry.nextIndex(current: 0, count: 2, reverse: true) == 1)
    }

    @Test func mapRectPreservesFractions() {
        let source = CGRect(x: 0, y: 0, width: 100, height: 100)
        let target = CGRect(x: 200, y: 50, width: 400, height: 200)
        let rect = CGRect(x: 25, y: 25, width: 50, height: 50)
        let mapped = Geometry.mapRect(rect, from: source, to: target)
        #expect(mapped.origin.x == 300)
        #expect(mapped.origin.y == 100)
        #expect(mapped.width == 200)
        #expect(mapped.height == 100)
    }

    @Test func nearestWindowInDirection() {
        let origin = CGRect(x: 100, y: 100, width: 80, height: 80)
        let right = CGRect(x: 400, y: 110, width: 80, height: 80)
        let left = CGRect(x: -200, y: 90, width: 80, height: 80)
        let up = CGRect(x: 110, y: 400, width: 80, height: 80)
        let frames = [right, left, up]
        #expect(Geometry.nearestIndex(origin: origin, direction: .right, frames: frames) == 0)
        #expect(Geometry.nearestIndex(origin: origin, direction: .left, frames: frames) == 1)
        #expect(Geometry.nearestIndex(origin: origin, direction: .up, frames: frames) == 2)
    }

    @Test func sortDisplaysLeftToRight() {
        let a = CGRect(x: 1920, y: 0, width: 1000, height: 800)
        let b = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        #expect(Geometry.sortDisplayOrder([a, b]) == [1, 0])
    }
}
