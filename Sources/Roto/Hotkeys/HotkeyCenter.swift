import Carbon
import Foundation
import RotoCore

final class HotkeyCenter: @unchecked Sendable {
    private var refs: [EventHotKeyRef] = []
    private var actions: [UInt32: BoundAction] = [:]
    private var handlerRef: EventHandlerRef?
    private let lock = NSLock()
    var onAction: (@MainActor (BoundAction) -> Void)?

    deinit {
        unregisterAll()
        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
    }

    func install() {
        lock.lock()
        defer { lock.unlock() }
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        var ref: EventHandlerRef?
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            rotoHotkeyCallback,
            1,
            &spec,
            userData,
            &ref
        )
        if status == noErr {
            handlerRef = ref
        }
    }

    func rebind(_ bindings: [(KeyCombo, BoundAction)]) {
        unregisterAll()
        lock.lock()
        defer { lock.unlock() }
        for (index, pair) in bindings.enumerated() {
            let id = UInt32(index + 1)
            let hotKeyID = EventHotKeyID(signature: OSType(0x726F746F), id: id) // 'roto'
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                pair.0.keyCode,
                pair.0.carbonModifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &ref
            )
            if status == noErr, let ref {
                refs.append(ref)
                actions[id] = pair.1
            }
        }
    }

    fileprivate func invoke(id: UInt32) {
        lock.lock()
        let action = actions[id]
        lock.unlock()
        guard let action else { return }
        DispatchQueue.main.async { [onAction] in
            Task { @MainActor in
                onAction?(action)
            }
        }
    }

    private func unregisterAll() {
        lock.lock()
        let current = refs
        refs.removeAll()
        actions.removeAll()
        lock.unlock()
        for ref in current {
            UnregisterEventHotKey(ref)
        }
    }
}

private func rotoHotkeyCallback(
    _: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return noErr }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return noErr }
    let center = Unmanaged<HotkeyCenter>.fromOpaque(userData).takeUnretainedValue()
    center.invoke(id: hotKeyID.id)
    return noErr
}
