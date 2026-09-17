import CoreGraphics
import Foundation

/// Geometry in two spaces:
/// - Cocoa: origin at the bottom-left of the primary display, y increases up.
/// - AX / Quartz: origin at the top-left of the primary display, y increases down.
///
/// `primaryMaxY` is the Cocoa y of the top edge of the primary display
/// (`NSScreen` whose `frame.origin` is `(0,0)`, typically `frame.maxY`).
public enum Geometry {
    public static func cocoaToAX(_ rect: CGRect, primaryMaxY: CGFloat) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: primaryMaxY - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    public static func axToCocoa(_ rect: CGRect, primaryMaxY: CGFloat) -> CGRect {
        cocoaToAX(rect, primaryMaxY: primaryMaxY)
    }

    public static func displayIndex(containing point: CGPoint, frames: [CGRect]) -> Int? {
        frames.enumerated()
            .filter { $0.element.contains(point) }
            .min(by: { lhs, rhs in
                area(lhs.element) < area(rhs.element)
            })?
            .offset
    }

    public static func displayIndex(containing rect: CGRect, frames: [CGRect]) -> Int? {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        if let index = displayIndex(containing: center, frames: frames) { return index }

        // A window can straddle unequal-height displays with its center in a desktop gap.
        // Preserve center-based selection when possible, otherwise use the largest overlap.
        let candidates = frames.enumerated().filter { !$0.element.isEmpty && !$0.element.isNull }
        let overlapping = candidates.map { entry in
            (index: entry.offset, area: area(rect.intersection(entry.element)))
        }.filter { $0.area > 0 }
        if let best = overlapping.max(by: { $0.area < $1.area }) { return best.index }

        // Recover windows left outside the desktop after a display is disconnected.
        return candidates.min { lhs, rhs in
            distance(center, to: lhs.element) < distance(center, to: rhs.element)
        }?.offset
    }

    public static func nextIndex(current: Int, count: Int, reverse: Bool) -> Int {
        guard count > 0 else { return 0 }
        let c = ((current % count) + count) % count
        if reverse {
            return (c - 1 + count) % count
        }
        return (c + 1) % count
    }

    /// Preserve fractional position and size where possible, keeping the result inside `target`.
    public static func mapRect(_ rect: CGRect, from source: CGRect, to target: CGRect) -> CGRect {
        let fx = source.width == 0 ? 0 : (rect.minX - source.minX) / source.width
        let fy = source.height == 0 ? 0 : (rect.minY - source.minY) / source.height
        let fw = source.width == 0 ? 1 : rect.width / source.width
        let fh = source.height == 0 ? 1 : rect.height / source.height
        let width = min(max(0, fw * target.width), target.width)
        let height = min(max(0, fh * target.height), target.height)
        return CGRect(
            x: min(max(target.minX + fx * target.width, target.minX), target.maxX - width),
            y: min(max(target.minY + fy * target.height, target.minY), target.maxY - height),
            width: width,
            height: height
        )
    }

    public static func centered(size: CGSize, in frame: CGRect) -> CGRect {
        CGRect(
            x: frame.midX - size.width / 2,
            y: frame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    /// Pick the nearest window in `direction`. Coordinates are Cocoa (y-up).
    public static func nearestIndex(origin: CGRect, direction: Direction, frames: [CGRect]) -> Int? {
        let oc = CGPoint(x: origin.midX, y: origin.midY)
        var best: (Int, CGFloat)?
        for (index, frame) in frames.enumerated() {
            let c = CGPoint(x: frame.midX, y: frame.midY)
            let dx = c.x - oc.x
            let dy = c.y - oc.y
            let inDirection: Bool
            switch direction {
            case .left: inDirection = dx < -1
            case .right: inDirection = dx > 1
            case .up: inDirection = dy > 1
            case .down: inDirection = dy < -1
            }
            if !inDirection { continue }

            let overlap: CGFloat
            switch direction {
            case .left, .right:
                overlap = overlap1D(origin.minY, origin.maxY, frame.minY, frame.maxY)
            case .up, .down:
                overlap = overlap1D(origin.minX, origin.maxX, frame.minX, frame.maxX)
            }
            let dist = hypot(dx, dy)
            let score = dist - overlap * 0.5
            if let current = best {
                if score < current.1 {
                    best = (index, score)
                }
            } else {
                best = (index, score)
            }
        }
        return best?.0
    }

    public static func sortDisplayOrder(_ frames: [CGRect]) -> [Int] {
        frames.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.minX != rhs.element.minX {
                    return lhs.element.minX < rhs.element.minX
                }
                return lhs.element.minY < rhs.element.minY
            }
            .map(\.offset)
    }

    private static func area(_ r: CGRect) -> CGFloat { r.isNull ? 0 : r.width * r.height }

    private static func distance(_ point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }

    private static func overlap1D(_ a0: CGFloat, _ a1: CGFloat, _ b0: CGFloat, _ b1: CGFloat) -> CGFloat {
        max(0, min(a1, b1) - max(a0, b0))
    }
}
