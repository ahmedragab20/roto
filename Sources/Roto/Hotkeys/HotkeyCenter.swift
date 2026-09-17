import Carbon
import Foundation
import RotoCore

/// Native boundary kept injectable so tests never register real global shortcuts.
struct HotkeyBackend {
    var install: (UnsafeMutableRawPointer) -> (OSStatus, EventHandlerRef?)
    var register: (KeyCombo, UInt32) -> (OSStatus, EventHotKeyRef?)
    var unregister: (EventHotKeyRef) -> Void
    var removeHandler: (EventHandlerRef) -> Void

    static var carbon: HotkeyBackend {
        HotkeyBackend(
            install: { userData in
                var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
                var ref: EventHandlerRef?
                let status = InstallEventHandler(GetApplicationEventTarget(), rotoHotkeyCallback, 1, &spec, userData, &ref)
                return (status, ref)
            },
            register: { combo, id in
                var ref: EventHotKeyRef?
                let hotKeyID = EventHotKeyID(signature: OSType(0x726F746F), id: id)
                let status = RegisterEventHotKey(combo.keyCode, combo.carbonModifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
                return (status, ref)
            },
            unregister: { UnregisterEventHotKey($0) },
            removeHandler: { RemoveEventHandler($0) }
        )
    }
}

struct HotkeyIssue: Equatable, Sendable {
    let shortcut: String?
    let status: OSStatus

    var message: String {
        if let shortcut {
            return "Shortcut \(shortcut) unavailable (macOS \(status)). Check conflicts, then Reload config."
        }
        return "Global shortcut handler unavailable (macOS \(status)). Try Reload config."
    }
}

final class HotkeyCenter: @unchecked Sendable {
    typealias Delivery = @MainActor @Sendable () -> Void
    private let backend: HotkeyBackend
    private let enqueue: (@escaping Delivery) -> Void
    private var refs: [EventHotKeyRef] = []
    private var actions: [UInt32: BoundAction] = [:]
    private var handlerRef: EventHandlerRef?
    private let lock = NSLock()
    private var bindings: [(KeyCombo, BoundAction)] = []
    private var suspended = false
    private var registrationIssues: [HotkeyIssue] = []
    private var installIssue: HotkeyIssue?
    private var nextID: UInt32 = 1
    private var generation: UInt64 = 0
    var onAction: (@MainActor (BoundAction) -> Void)?
    var onIssuesChanged: (@MainActor ([HotkeyIssue]) -> Void)?

    var issues: [HotkeyIssue] { lock.withLock { registrationIssues } }

    init(backend: HotkeyBackend = .carbon, enqueue: @escaping (@escaping Delivery) -> Void = { work in
        DispatchQueue.main.async(execute: work)
    }) {
        self.backend = backend
        self.enqueue = enqueue
    }

    deinit {
        unregisterAll()
        if let handlerRef { backend.removeHandler(handlerRef) }
    }

    func install() {
        lock.lock()
        guard handlerRef == nil else {
            lock.unlock()
            return
        }
        let (status, ref) = backend.install(Unmanaged.passUnretained(self).toOpaque())
        if status == noErr, let ref {
            handlerRef = ref
            installIssue = nil
        } else {
            installIssue = HotkeyIssue(shortcut: nil, status: status == noErr ? OSStatus(paramErr) : status)
        }
        registrationIssues = installIssue.map { [$0] } ?? []
        lock.unlock()
        publishIssues()
    }

    func rebind(_ bindings: [(KeyCombo, BoundAction)]) {
        install() // A reload can recover from an earlier handler installation failure.
        unregisterAll()
        lock.lock()
        self.bindings = bindings
        registrationIssues = installIssue.map { [$0] } ?? []
        if !suspended, handlerRef != nil {
            for (combo, action) in bindings {
                // Never reuse a retired registration's ID, including after recorder suspension.
                guard nextID != 0 else {
                    registrationIssues.append(HotkeyIssue(shortcut: combo.canonical, status: OSStatus(paramErr)))
                    continue
                }
                let id = nextID
                nextID = id == .max ? 0 : id + 1
                let (status, ref) = backend.register(combo, id)
                if status == noErr, let ref {
                    refs.append(ref)
                    actions[id] = action
                } else {
                    registrationIssues.append(HotkeyIssue(shortcut: combo.canonical, status: status == noErr ? OSStatus(paramErr) : status))
                }
            }
        }
        lock.unlock()
        publishIssues()
    }

    /// Reloads update the stored bindings even while recording has unregistered the hotkeys.
    func setSuspended(_ value: Bool) {
        lock.lock()
        guard suspended != value else {
            lock.unlock()
            return
        }
        suspended = value
        let current = bindings
        lock.unlock()
        rebind(current)
    }

    func invoke(id: UInt32) {
        lock.lock()
        let action = actions[id]
        let request = generation
        lock.unlock()
        guard let action else { return }
        enqueue { [weak self, onAction] in
            guard let self, self.lock.withLock({ self.generation == request && !self.suspended }) else { return }
            onAction?(action)
        }
    }

    private func publishIssues() {
        let (snapshot, request) = lock.withLock { (registrationIssues, generation) }
        enqueue { [weak self, onIssuesChanged] in
            guard let self, self.lock.withLock({ self.generation == request }) else { return }
            onIssuesChanged?(snapshot)
        }
    }

    private func unregisterAll() {
        lock.lock()
        generation &+= 1
        let current = refs
        refs.removeAll()
        actions.removeAll()
        lock.unlock()
        for ref in current { backend.unregister(ref) }
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
    guard status == noErr, hotKeyID.signature == OSType(0x726F746F) else { return OSStatus(eventNotHandledErr) }
    let center = Unmanaged<HotkeyCenter>.fromOpaque(userData).takeUnretainedValue()
    center.invoke(id: hotKeyID.id)
    return noErr
}
