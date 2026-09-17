import Carbon
import Testing
import RotoCore
@testable import Roto

@MainActor
struct HotkeyCenterTests {
    @Test func retiredRegistrationCannotInvokeNewBinding() throws {
        let native = FakeHotkeys()
        let queue = HotkeyDeliveries()
        let center = HotkeyCenter(backend: native.backend, enqueue: queue.enqueue)
        var actions: [BoundAction] = []
        center.onAction = { actions.append($0) }
        center.install()
        center.rebind([(try KeyCombo.parse("ctrl+a"), .clipboard)])
        let oldID = try #require(native.registrations.last?.id)
        center.rebind([(try KeyCombo.parse("ctrl+b"), .emoji)])
        let newID = try #require(native.registrations.last?.id)
        #expect(newID != oldID)
        center.invoke(id: oldID)
        queue.drain()
        #expect(actions.isEmpty)
        actions.removeAll()
        center.invoke(id: newID)
        queue.drain()
        #expect(actions == [.emoji])
    }

    @Test(arguments: [false, true])
    func queuedActionIsCancelledByRebindOrRecording(recording: Bool) throws {
        let native = FakeHotkeys()
        let queue = HotkeyDeliveries()
        let center = HotkeyCenter(backend: native.backend, enqueue: queue.enqueue)
        var actions: [BoundAction] = []
        center.onAction = { actions.append($0) }
        center.install()
        center.rebind([(try KeyCombo.parse("ctrl+a"), .clipboard)])
        center.invoke(id: try #require(native.registrations.last?.id))
        if recording {
            center.setSuspended(true)
            center.setSuspended(false)
        } else {
            center.rebind([(try KeyCombo.parse("ctrl+b"), .emoji)])
        }
        queue.drain()
        #expect(actions.isEmpty)
    }

    @Test func reportsFailedRegistrationsWithoutDisablingSuccessfulOnes() throws {
        let native = FakeHotkeys()
        let queue = HotkeyDeliveries()
        let center = HotkeyCenter(backend: native.backend, enqueue: queue.enqueue)
        let good = try KeyCombo.parse("ctrl+a")
        let bad = try KeyCombo.parse("ctrl+b")
        native.failKeys = [bad.keyCode]
        var actions: [BoundAction] = []
        var reports: [[HotkeyIssue]] = []
        center.onAction = { actions.append($0) }
        center.onIssuesChanged = { reports.append($0) }
        center.install()
        center.rebind([(good, .clipboard), (bad, .emoji)])
        let expected = HotkeyIssue(shortcut: bad.canonical, status: -9878)
        #expect(center.issues == [expected])
        for registration in native.registrations { center.invoke(id: registration.id) }
        queue.drain()
        #expect(actions == [.clipboard])
        #expect(reports.last == [expected])

        native.failKeys = []
        center.rebind([(bad, .emoji)])
        queue.drain()
        #expect(center.issues.isEmpty)
        #expect(reports.last == [])
    }

    @Test func failedHandlerIsReportedAndRetriedWithoutReservingDeadHotkeys() throws {
        let native = FakeHotkeys()
        let queue = HotkeyDeliveries()
        let center = HotkeyCenter(backend: native.backend, enqueue: queue.enqueue)
        native.installStatus = -9874
        center.install()
        center.rebind([(try KeyCombo.parse("ctrl+a"), .clipboard)])
        #expect(center.issues == [HotkeyIssue(shortcut: nil, status: -9874)])
        #expect(native.registrations.isEmpty)
        native.installStatus = noErr
        center.rebind([(try KeyCombo.parse("ctrl+a"), .clipboard)])
        #expect(center.issues.isEmpty)
        #expect(native.registrations.count == 1)
    }

    @Test func recordingRestoresLatestBindingsAndReleasesResources() throws {
        let native = FakeHotkeys()
        let queue = HotkeyDeliveries()
        var center: HotkeyCenter? = HotkeyCenter(backend: native.backend, enqueue: queue.enqueue)
        var actions: [BoundAction] = []
        center?.onAction = { actions.append($0) }
        center?.install()
        center?.rebind([(try KeyCombo.parse("ctrl+a"), .clipboard)])
        #expect(native.active.count == 1)
        center?.setSuspended(true)
        #expect(native.active.isEmpty)
        center?.rebind([(try KeyCombo.parse("ctrl+b"), .emoji)])
        #expect(native.active.isEmpty)
        center?.setSuspended(false)
        #expect(native.active.count == 1)
        center?.invoke(id: try #require(native.registrations.last?.id))
        queue.drain()
        #expect(actions == [.emoji])
        center = nil
        #expect(native.active.isEmpty)
        #expect(native.handlerRemoved)
    }
}

@MainActor
private final class HotkeyDeliveries {
    var pending: [HotkeyCenter.Delivery] = []
    func enqueue(_ work: @escaping HotkeyCenter.Delivery) { pending.append(work) }
    func drain() {
        let current = pending
        pending.removeAll()
        current.forEach { $0() }
    }
}

@MainActor
private final class FakeHotkeys {
    var registrations: [(combo: KeyCombo, id: UInt32)] = []
    var active: Set<UInt32> = []
    var failKeys: Set<UInt32> = []
    var installStatus: OSStatus = noErr
    var handlerRemoved = false

    var backend: HotkeyBackend {
        HotkeyBackend(
            install: { _ in (self.installStatus, self.installStatus == noErr ? OpaquePointer(bitPattern: 0xFFFF) : nil) },
            register: { combo, id in
                self.registrations.append((combo, id))
                if self.failKeys.contains(combo.keyCode) { return (-9878, nil) }
                self.active.insert(id)
                return (noErr, OpaquePointer(bitPattern: Int(id)))
            },
            unregister: { self.active.remove(UInt32(Int(bitPattern: $0))) },
            removeHandler: { _ in self.handlerRemoved = true }
        )
    }
}
