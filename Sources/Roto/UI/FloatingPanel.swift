import AppKit
import os
import Quartz
import RotoCore

/// Feeds Quick Look the files a popup wants to show.
final class QuickLookSource: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate, @unchecked Sendable {
    var urls: [URL] = []

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        urls.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        urls.indices.contains(index) ? urls[index] as NSURL : nil
    }
}

/// Borderless popup that takes keyboard focus without activating roto.
///
/// The app you were typing in stays frontmost the whole time, so when the panel
/// hides, keyboard focus goes straight back to the same text field and a
/// synthetic ⌘V or typed glyph lands there. No AX focus juggling: poking a
/// field's AXFocused makes many apps select its whole contents, and the paste
/// would then replace everything.
@MainActor
final class FloatingPanel: NSPanel {
    var onKeyDown: ((NSEvent) -> Bool)?
    var onDismiss: (() -> Void)?
    /// Receives focus every time the panel is shown.
    weak var focusView: NSView?

    private(set) var previousApp: NSRunningApplication?
    private var keyMonitor: Any?
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var otherAppObserver: NSObjectProtocol?
    private var displayLink: CADisplayLink?
    private var motion: Motion?
    private var focusTimer: Timer?
    private var focusWatch = FocusWatch()
    private var activationObserver: NSObjectProtocol?
    private var pendingInsertion: (@MainActor () -> Void)?
    /// Bumped on every show/hide so a stale fade-out cannot hide a newer showing.
    private var generation = 0
    private let quickLook = QuickLookSource()
    /// Set before Quick Look takes the keyboard, so losing key status then is not a dismissal.
    private var quickLookActive = false

    init(size: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        // Above ordinary floating windows (picture-in-picture, palettes).
        level = .modalPanel
        isOpaque = false
        backgroundColor = .clear
        // Dragging from a row should never move the window instead of clicking it.
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isReleasedWhenClosed = false
        hasShadow = true
        animationBehavior = .none
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    var isShown: Bool {
        isVisible && generation % 2 == 1
    }

    func embed(rootView: NSView, cornerRadius: CGFloat = 24) {
        let size = frame.size
        rootView.autoresizingMask = [.width, .height]
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: NSRect(origin: .zero, size: size))
            glass.autoresizingMask = [.width, .height]
            glass.cornerRadius = cornerRadius
            glass.style = .regular
            rootView.frame = glass.bounds
            glass.contentView = rootView
            contentView = glass
        } else {
            let visual = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
            visual.autoresizingMask = [.width, .height]
            visual.material = .hudWindow
            visual.blendingMode = .behindWindow
            visual.state = .active
            visual.wantsLayer = true
            visual.layer?.cornerRadius = cornerRadius
            visual.layer?.masksToBounds = true
            rootView.frame = visual.bounds
            visual.addSubview(rootView)
            contentView = visual
        }
    }

    func present(screen: PopupScreen) {
        if generation % 2 == 0 {
            generation += 1
        }
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != NSRunningApplication.current.processIdentifier {
            previousApp = front
        }
        let appearing = !isVisible
        stopMotion()
        setFrameOrigin(ScreenService.panelOrigin(size: frame.size, screen: screen))
        installMonitors()

        if appearing {
            alphaValue = 0
            makeKeyAndOrderFront(nil)
            let scale = PanelMotion.scalesWindow ? PanelMotion.appearScale : 1
            // Still transparent, so starting small never flashes at full size.
            WindowScale.set(scale, on: self)
            startMotion(Motion(kind: .appear, start: CACurrentMediaTime(), fromScale: scale, toScale: 1))
        } else {
            // Shown again while fading out: snap back.
            WindowScale.set(1, on: self)
            alphaValue = 1
            makeKeyAndOrderFront(nil)
        }
        if let focusView {
            makeFirstResponder(focusView)
        }
    }

    func dismiss(animated: Bool = true) {
        guard generation % 2 == 1 else { return }
        generation += 1
        let current = generation
        removeMonitors()
        if isQuickLookVisible {
            QLPreviewPanel.shared()?.orderOut(nil)
        }

        if animated {
            let scale = PanelMotion.scalesWindow ? PanelMotion.disappearScale : 1
            startMotion(Motion(kind: .disappear(generation: current), start: CACurrentMediaTime(), fromScale: 1, toScale: scale))
        } else {
            stopMotion()
            finishDismiss(generation: current)
        }
    }

    private func finishDismiss(generation current: Int) {
        guard generation == current else { return }
        orderOut(nil)
        WindowScale.set(1, on: self)
        alphaValue = 1
        // Only needed when something (a click on a banner button) activated roto;
        // normally the previous app never lost focus.
        if NSApp.isActive, let previousApp, !previousApp.isTerminated {
            NSApp.yieldActivation(to: previousApp)
            previousApp.activate(from: .current, options: [])
        }
        onDismiss?()
    }

    /// Hides at once, waits until the previous app is frontmost again, then runs
    /// `insert` (a synthetic paste or typed text) so it lands in that app.
    func dismissForInsertion(_ insert: @escaping @MainActor () -> Void) {
        let target = previousApp
        dismiss(animated: false)

        guard let target, !target.isTerminated else {
            insert()
            return
        }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier {
            // Give the window server a beat to hand key focus back.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { insert() }
            return
        }

        pendingInsertion = insert
        let targetPID = target.processIdentifier
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.processIdentifier == targetPID else { return }
            MainActor.assumeIsolated { self?.runPendingInsertion() }
        }
        target.activate()
        // Never hang: insert anyway if the activation notice does not arrive.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.runPendingInsertion()
        }
    }

    private func runPendingInsertion() {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        guard let insert = pendingInsertion else { return }
        pendingInsertion = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { insert() }
    }

    override func cancelOperation(_ sender: Any?) {
        dismiss()
    }

    // MARK: - Motion

    private struct Motion {
        enum Kind {
            case appear
            case disappear(generation: Int)
        }

        let kind: Kind
        let start: CFTimeInterval
        let fromScale: CGFloat
        let toScale: CGFloat
    }

    private func startMotion(_ next: Motion) {
        motion = next
        if displayLink == nil, let link = contentView?.displayLink(target: self, selector: #selector(stepMotion(_:))) {
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
        stepMotion(nil)
    }

    private func stopMotion() {
        motion = nil
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func stepMotion(_ link: CADisplayLink?) {
        guard let motion else {
            stopMotion()
            return
        }
        let elapsed = CACurrentMediaTime() - motion.start
        let scales = motion.fromScale != motion.toScale

        switch motion.kind {
        case .appear:
            alphaValue = PanelMotion.easeOut(elapsed / PanelMotion.appearFade)
            if scales {
                let progress = PanelMotion.spring(elapsed)
                WindowScale.set(motion.fromScale + (motion.toScale - motion.fromScale) * progress, on: self)
            }
            if elapsed >= (scales ? PanelMotion.appearSettle : PanelMotion.appearFade) {
                stopMotion()
                WindowScale.set(1, on: self)
                alphaValue = 1
            }
        case .disappear(let generation):
            let progress = PanelMotion.easeIn(elapsed / PanelMotion.disappearDuration)
            alphaValue = 1 - progress
            if scales {
                WindowScale.set(1 + (motion.toScale - 1) * progress, on: self)
            }
            if elapsed >= PanelMotion.disappearDuration {
                stopMotion()
                finishDismiss(generation: generation)
            }
        }
    }

    // MARK: - Quick Look

    var isQuickLookVisible: Bool {
        QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared()?.isVisible == true
    }

    /// Shows `urls` in Quick Look over the popup, or closes Quick Look if it is open.
    func toggleQuickLook(_ urls: [URL]) {
        guard let preview = QLPreviewPanel.shared() else { return }
        if isQuickLookVisible {
            preview.orderOut(nil)
            makeKey()
            return
        }
        quickLook.urls = urls
        quickLookActive = true
        preview.makeKeyAndOrderFront(nil)
        preview.reloadData()
    }

    nonisolated override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        MainActor.assumeIsolated { !quickLook.urls.isEmpty }
    }

    nonisolated override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = quickLook
            panel.delegate = quickLook
        }
    }

    nonisolated override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = nil
            panel.delegate = nil
            quickLook.urls = []
            quickLookActive = false
            // Quick Look closed with the popup still up: give the popup the keyboard back.
            if isShown {
                makeKey()
            }
        }
    }

    // MARK: - Monitors

    private func installMonitors() {
        removeMonitors()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self else { return event }
            // Let an input method finish composing before arrows/return/escape act on the list.
            if let editor = self.firstResponder as? NSTextView, editor.hasMarkedText() {
                return event
            }
            if self.onKeyDown?(event) == true {
                return nil
            }
            return self.performEditingShortcut(event) ? nil : event
        }

        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let self, event.window !== self, !(event.window is QLPreviewPanel) {
                self.dismiss()
            }
            return event
        }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.frame.contains(NSEvent.mouseLocation) else { return }
                self.dismiss()
            }
        }

        // Another app coming forward (⌘Tab, a Dock click, an app's own hotkey).
        otherAppObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let pid = app?.processIdentifier
            let bundleID = app?.bundleIdentifier ?? "?"
            MainActor.assumeIsolated {
                guard let self, let pid, pid != NSRunningApplication.current.processIdentifier,
                      pid != self.previousApp?.processIdentifier
                else { return }
                self.closeForFocusLoss("\(bundleID) activated")
            }
        }

        // Spotlight, Raycast and Alfred take the keyboard without activating anything
        // or making this panel resign key, so watch for that directly while shown.
        focusWatch = FocusWatch(launcherPIDs: FocusProbe.launcherPIDs())
        focusWatch.launcherWasVisible = FocusProbe.hasLauncherWindow(ownedBy: focusWatch.launcherPIDs)
        focusTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.checkKeyboardFocus()
            }
        }
        focusTimer?.tolerance = 0.05

        // ⌘Tab, Mission Control, another app's hotkey: anything that takes focus closes the panel.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: self,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                // Quick Look takes the keyboard while it is open; that is not leaving the popup.
                guard let self, !self.quickLookActive, !self.isQuickLookVisible else { return }
                self.dismiss()
            }
        }
    }

    private func removeMonitors() {
        for monitor in [keyMonitor, localClickMonitor, globalClickMonitor].compactMap({ $0 }) {
            NSEvent.removeMonitor(monitor)
        }
        keyMonitor = nil
        localClickMonitor = nil
        globalClickMonitor = nil
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
        }
        if let otherAppObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(otherAppObserver)
            self.otherAppObserver = nil
        }
        focusTimer?.invalidate()
        focusTimer = nil
    }

    private func checkKeyboardFocus() {
        guard isShown, !quickLookActive, !isQuickLookVisible else { return }

        let launcherVisible = FocusProbe.hasLauncherWindow(ownedBy: focusWatch.launcherPIDs)
        if launcherVisible && !focusWatch.launcherWasVisible {
            closeForFocusLoss("launcher window appeared")
            return
        }
        focusWatch.launcherWasVisible = launcherVisible

        // Only trust the system-wide focus once it has pointed at this panel, and
        // need two readings in a row elsewhere, so a stale answer never closes it.
        guard let pid = FocusProbe.keyboardFocusPID() else { return }
        if pid == NSRunningApplication.current.processIdentifier {
            focusWatch.sawOwnFocus = true
            focusWatch.foreignReadings = 0
        } else if focusWatch.sawOwnFocus {
            focusWatch.foreignReadings += 1
            if focusWatch.foreignReadings >= 2 {
                let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "pid \(pid)"
                closeForFocusLoss("keyboard focus moved to \(bundleID)")
            }
        }
    }

    private func closeForFocusLoss(_ reason: String) {
        FocusProbe.log.notice("closing popup: \(reason, privacy: .public)")
        dismiss(animated: false)
    }

    /// roto has no Edit menu, so ⌘A/⌘C/⌘X/⌘V/⌘Z would do nothing in the search field.
    private func performEditingShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let action: Selector
        switch (PanelKey.letter(event), flags) {
        case ("a", .command): action = #selector(NSResponder.selectAll(_:))
        case ("c", .command): action = #selector(NSText.copy(_:))
        case ("x", .command): action = #selector(NSText.cut(_:))
        case ("v", .command): action = #selector(NSText.paste(_:))
        case ("z", .command): action = Selector(("undo:"))
        case ("z", [.command, .shift]): action = Selector(("redo:"))
        default: return false
        }
        return NSApp.sendAction(action, to: nil, from: self)
    }
}

private struct FocusWatch {
    var launcherPIDs: Set<pid_t> = []
    var launcherWasVisible = false
    var sawOwnFocus = false
    var foreignReadings = 0
}

/// Cheap checks for "something else now has the keyboard", polled while a popup is up.
@MainActor
enum FocusProbe {
    nonisolated static let log = Logger(subsystem: "dev.roto.app", category: "popup")

    /// Search launchers that float a panel over everything without activating.
    private static let launcherBundleIDs = [
        "com.apple.Spotlight",
        "com.raycast.macos",
        "com.runningwithcrayons.Alfred",
    ]

    static func launcherPIDs() -> Set<pid_t> {
        Set(launcherBundleIDs.flatMap {
            NSRunningApplication.runningApplications(withBundleIdentifier: $0).map(\.processIdentifier)
        })
    }

    /// A panel-sized, visible window from a launcher (its menu bar icon is too small to count).
    static func hasLauncherWindow(ownedBy pids: Set<pid_t>) -> Bool {
        guard !pids.isEmpty,
              let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
        else { return false }
        return info.contains { entry in
            guard let pid = entry[kCGWindowOwnerPID as String] as? pid_t, pids.contains(pid),
                  (entry[kCGWindowAlpha as String] as? Double ?? 1) > 0.01,
                  let bounds = entry[kCGWindowBounds as String] as? [String: Any],
                  let width = bounds["Width"] as? CGFloat,
                  let height = bounds["Height"] as? CGFloat
            else { return false }
            return width >= 200 && height >= 40
        }
    }

    /// The process that owns keyboard focus right now, even for non-activating panels.
    static func keyboardFocusPID() -> pid_t? {
        let system = AXUIElementCreateSystemWide()
        guard let app = AXSupport.copy(system, kAXFocusedApplicationAttribute as String) else { return nil }
        return AXSupport.pid(of: app as! AXUIElement)
    }
}

/// Timing for the popup scale-in/out, modeled on Spotlight's panel.
@MainActor
enum PanelMotion {
    static let appearScale: CGFloat = 0.94
    static let disappearScale: CGFloat = 0.97
    static let appearFade: CFTimeInterval = 0.12
    /// A 0.3 s response spring with 0.78 damping is at rest (within 0.1%) by then.
    static let appearSettle: CFTimeInterval = 0.42
    static let disappearDuration: CFTimeInterval = 0.12

    /// Reduce Motion keeps the fades and drops the scaling.
    static var scalesWindow: Bool {
        WindowScale.isAvailable && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Damped spring from 0 to 1; slight overshoot, then settles.
    static func spring(_ time: CFTimeInterval) -> CGFloat {
        let damping = 0.78
        let omega = 2 * Double.pi / 0.3
        let decay = damping * omega
        let damped = omega * (1 - damping * damping).squareRoot()
        let t = max(time, 0)
        return CGFloat(1 - exp(-decay * t) * (cos(damped * t) + decay / damped * sin(damped * t)))
    }

    static func easeOut(_ progress: Double) -> CGFloat {
        let p = min(max(progress, 0), 1)
        return CGFloat(1 - pow(1 - p, 3))
    }

    static func easeIn(_ progress: Double) -> CGFloat {
        let p = min(max(progress, 0), 1)
        return CGFloat(p * p)
    }
}

/// Scales a window about its center in the window server, so its shadow and glass
/// scale with it (a layer transform would leave both at full size). Uses the same
/// private SkyLight call as window managers; if it is missing, popups just fade.
@MainActor
enum WindowScale {
    private struct Functions: @unchecked Sendable {
        let connection: @convention(c) () -> Int32
        let setTransform: @convention(c) (Int32, UInt32, CGAffineTransform) -> Int32
    }

    private static let functions: Functions? = {
        let handle = dlopen(nil, RTLD_NOW)
        guard let connection = dlsym(handle, "SLSMainConnectionID") ?? dlsym(handle, "CGSMainConnectionID"),
              let setTransform = dlsym(handle, "SLSSetWindowTransform") ?? dlsym(handle, "CGSSetWindowTransform")
        else { return nil }
        return Functions(
            connection: unsafeBitCast(connection, to: (@convention(c) () -> Int32).self),
            setTransform: unsafeBitCast(setTransform, to: (@convention(c) (Int32, UInt32, CGAffineTransform) -> Int32).self)
        )
    }()

    static var isAvailable: Bool {
        functions != nil
    }

    static func set(_ scale: CGFloat, on window: NSWindow) {
        guard let functions, window.windowNumber > 0 else { return }
        let scale = max(scale, 0.5)
        let frame = window.frame
        let primaryMaxY = NSScreen.screens.first { $0.frame.origin == .zero }?.frame.maxY ?? frame.maxY
        // The transform maps screen points (top-left origin) to window points; at
        // scale 1 it is just the window origin, as the window server sets it.
        let width = frame.width * scale
        let height = frame.height * scale
        let x = frame.minX + (frame.width - width) / 2
        let y = (primaryMaxY - frame.maxY) + (frame.height - height) / 2
        let transform = CGAffineTransform(scaleX: 1 / scale, y: 1 / scale).translatedBy(x: -x, y: -y)
        _ = functions.setTransform(functions.connection(), UInt32(window.windowNumber), transform)
    }
}
