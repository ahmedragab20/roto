import ApplicationServices
import Foundation
import Testing
@testable import Roto

struct WindowFrameWriterTests {
    @Test func normalFrameWriteAndTransientFirstMoveFailure() {
        for initialFailure in [false, true] {
            var frame = CGRect(x: 0, y: 0, width: 800, height: 600)
            var moves = 0
            let writer = WindowFrameWriter(
                setPosition: { point in
                    moves += 1
                    if initialFailure && moves == 1 { return .cannotComplete }
                    frame.origin = point
                    return .success
                },
                setSize: { frame.size = $0; return .success },
                readFrame: { frame }
            )
            let destination = CGRect(x: -1200, y: 500, width: 900, height: 700)
            #expect(writer.apply(destination) == nil)
            #expect(frame == destination)
        }
    }

    @Test func rejectedWritesAndSilentNoOpAreReported() {
        let initial = CGRect(x: 0, y: 0, width: 800, height: 600)
        let requested = CGRect(x: 1200, y: 100, width: 600, height: 500)
        for status in [AXError.cannotComplete, .success] {
            let writer = WindowFrameWriter(setPosition: { _ in status }, setSize: { _ in status }, readFrame: { initial })
            #expect(writer.apply(requested) != nil)
        }
        let unreadable = WindowFrameWriter(setPosition: { _ in .success }, setSize: { _ in .success }, readFrame: { nil })
        #expect(unreadable.apply(requested) != nil)
    }

    @Test func minimumSizeIsReadBackBeforeFinalPosition() {
        var frame = CGRect(x: 0, y: 0, width: 1200, height: 900)
        let target = CGRect(x: -1500, y: 500, width: 1500, height: 950)
        let requested = CGRect(x: -600, y: 900, width: 600, height: 400)
        let writer = WindowFrameWriter(
            setPosition: { frame.origin = $0; return .success },
            setSize: { _ in frame.size = CGSize(width: 1000, height: 800); return .success },
            readFrame: { frame }
        )
        #expect(writer.apply(requested, bounds: target) != nil)
        #expect(frame == CGRect(x: -1000, y: 650, width: 1000, height: 800))
        #expect(target.contains(frame))
    }

    @Test func windowLargerThanDisplayKeepsItsTopLeftReachable() {
        var frame = CGRect(x: 0, y: 0, width: 1800, height: 1100)
        let target = CGRect(x: -1500, y: 500, width: 1500, height: 950)
        let writer = WindowFrameWriter(
            setPosition: { frame.origin = $0; return .success },
            setSize: { _ in .attributeUnsupported },
            readFrame: { frame }
        )
        #expect(writer.apply(CGRect(x: -700, y: 800, width: 700, height: 600), bounds: target) != nil)
        #expect(frame.origin == target.origin)
        #expect(frame.size == CGSize(width: 1800, height: 1100))
    }
}
