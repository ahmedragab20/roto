import AppKit
import os
import Quartz
import SwiftUI
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
    private let focusWatchdog = FocusWatchdog()
    private var activationObserver: NSObjectProtocol?
    private var pendingInsertion: (@MainActor () -> Void)?
    /// Bumped on every show/hide so a stale fade-out cannot hide a newer showing.
    private var generation = 0
    private let quickLook = QuickLookSource()
    /// Set before Quick Look takes the keyboard, so losing key status then is not
    /// a dismissal. Read through `isQuickLookOpen`, cleared only by `hideQuickLook`
    /// and by Quick Look closing itself.
    private var quickLookActive = false

    /// Transparent room left around the popup inside its window.
    ///
    /// Liquid Glass draws its own shadow and edge lighting outside the rounded
    /// shape. With the window ending exactly at that shape, the only place there
    /// is room for it to land is the four corners — where it showed up as a grey
    /// block outside each rounded corner. The older material is clipped by its own
    /// layer mask and needs no room, so it gets none.
    static let contentInset: CGFloat = {
        if #available(macOS 26.0, *) {
            return 32
        }
        return 0
    }()

    /// The visible popup, without the transparent margin around it.
    var contentFrame: NSRect {
        frame.insetBy(dx: Self.contentInset, dy: Self.contentInset)
    }

    init(size: NSSize) {
        let inset = Self.contentInset
        super.init(
            contentRect: NSRect(
                origin: .zero,
                size: NSSize(width: size.width + inset * 2, height: size.height + inset * 2)
            ),
            // Borderless panels already use the full content area; no titlebar extension is needed.
            styleMask: [.borderless, .nonactivatingPanel],
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

    /// The panel owns its size; long SwiftUI lists must scroll rather than resize the window.
    func embed<Content: View>(rootView: NSHostingView<Content>, cornerRadius: CGFloat = 24) {
        rootView.sizingOptions = []
        rootView.autoresizingMask = [.width, .height]
        let inset = Self.contentInset
        // Plain and unpainted: the margin around the material has to stay empty,
        // or it becomes the square the material was bleeding into.
        let container = NSView(frame: NSRect(origin: .zero, size: frame.size))
        container.autoresizingMask = [.width, .height]
        let bounds = NSRect(origin: .zero, size: frame.size).insetBy(dx: inset, dy: inset)

        if #available(macOS 26.0, *) {
            // Glass draws its own shadow; a second window shadow leaves a hard
            // dark rim around it.
            hasShadow = false
            let glass = NSGlassEffectView(frame: bounds)
            glass.autoresizingMask = [.width, .height]
            glass.cornerRadius = cornerRadius
            glass.style = .regular
            rootView.frame = glass.bounds
            glass.contentView = rootView
            container.addSubview(glass)
        } else {
            let visual = NSVisualEffectView(frame: bounds)
            visual.autoresizingMask = [.width, .height]
            visual.material = .hudWindow
            visual.blendingMode = .behindWindow
            visual.state = .active
            visual.wantsLayer = true
            visual.layer?.cornerRadius = cornerRadius
            visual.layer?.masksToBounds = true
            rootView.frame = visual.bounds
            visual.addSubview(rootView)
            container.addSubview(visual)
        }
        contentView = container
    }

    /// The material view inside the margin, for tests and layout checks.
    var popupView: NSView? {
        contentView?.subviews.first
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
        // A fresh showing never inherits a preview, so no stale state can survive
        // one and leave the next popup unable to close itself.
        hideQuickLook()
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
        hideQuickLook()

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
                let progress = PanelMotion.grow(elapsed / PanelMotion.appearGrow)
                WindowScale.set(motion.fromScale + (motion.toScale - motion.fromScale) * progress, on: self)
            }
            if elapsed >= (scales ? PanelMotion.appearDuration : PanelMotion.appearFade) {
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

    /// Quick Look belongs to this popup: asked for, and not closed since.
    ///
    /// Deliberately this popup's own intent rather than the shared panel's
    /// `isVisible`. That answer is wrong at both ends: the panel is not visible yet
    /// in the moment after it is asked to open, and it still reports itself visible
    /// while it animates away after being closed.
    var isQuickLookOpen: Bool {
        quickLookActive
    }

    /// Shows `urls` in Quick Look over the popup.
    func showQuickLook(_ urls: [URL]) {
        guard !urls.isEmpty, let preview = QLPreviewPanel.shared() else { return }
        quickLook.urls = urls
        quickLookActive = true
        preview.makeKeyAndOrderFront(nil)
        preview.reloadData()
    }

    /// Closes Quick Look and forgets it. Reports whether there was one to close.
    ///
    /// The bookkeeping cannot be left to `endPreviewPanelControl`: that never
    /// arrives when the preview is dismissed before it took control, and the flag
    /// left standing then told every auto-close path that the popup was still
    /// previewing — so the popup stopped closing itself for the rest of its life.
    @discardableResult
    func hideQuickLook() -> Bool {
        let wasOpen = isQuickLookOpen
        quickLookActive = false
        // Cleared before ordering out: a preview still opening asks to take
        // control, and an empty source refuses it, so it gives up instead of
        // appearing after the popup has already gone.
        quickLook.urls = []
        if QLPreviewPanel.sharedPreviewPanelExists() {
            QLPreviewPanel.shared()?.orderOut(nil)
        }
        return wasOpen
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
                // The transparent margin is not the popup: a click there is outside.
                guard let self, !self.contentFrame.contains(NSEvent.mouseLocation) else { return }
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
                guard let self, let pid, pid != NSRunningApplication.current.processIdentifier else { return }
                // The app the popup floats over stays frontmost the whole time, so
                // it coming forward is not the user leaving — unless Quick Look
                // pulled roto in front of it first, in which case that is exactly
                // what going back to it means.
                if pid == self.previousApp?.processIdentifier, !self.isQuickLookOpen {
                    return
                }
                self.closeForFocusLoss("\(bundleID) activated")
            }
        }

        // Spotlight, Raycast and Alfred take the keyboard without activating anything
        // or making this panel resign key, so watch for that directly while shown.
        focusWatchdog.start(launcherPIDs: FocusProbe.launcherPIDs(), token: generation) { [weak self] token, reason in
            guard let self, self.generation == token, self.isShown, !self.isQuickLookOpen
            else { return }
            self.closeForFocusLoss(reason)
        }

        // ⌘Tab, Mission Control, another app's hotkey: anything that takes focus closes the panel.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: self,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                // Quick Look takes the keyboard while it is open; that is not leaving the popup.
                guard let self, !self.isQuickLookOpen else { return }
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
        focusWatchdog.stop()
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

/// Watches for something else taking the keyboard while a popup is up.
///
/// Spotlight, Raycast and Alfred float a panel over everything without activating
/// and without making the popup resign key, so there is no notification to observe
/// — it has to be polled. The poll copies the window list and makes a blocking
/// Accessibility read, which is far too much to do on the main thread six times a
/// second while someone is typing, so it runs on a utility queue and only the
/// verdict comes back.
final class FocusWatchdog: @unchecked Sendable {
    private let queue = DispatchQueue(label: "roto.focus-watch", qos: .utility)
    private var timer: DispatchSourceTimer?
    /// Everything below is touched only on `queue`.
    private var launcherPIDs: Set<pid_t> = []
    private var launcherWasVisible = false
    private var sawOwnFocus = false
    private var foreignReadings = 0
    /// One verdict per showing; the timer is stopped from the main thread.
    private var delivered = false

    /// `token` is the showing this verdict belongs to; the panel drops a stale one.
    func start(
        launcherPIDs: Set<pid_t>,
        token: Int,
        onLoss: @escaping @MainActor (Int, String) -> Void
    ) {
        stop()
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let timer = DispatchSource.makeTimerSource(queue: queue)
        // The queue is serial, so this priming runs before the first tick.
        queue.async { [self] in
            self.launcherPIDs = launcherPIDs
            launcherWasVisible = FocusProbe.hasLauncherWindow(ownedBy: launcherPIDs)
            sawOwnFocus = false
            foreignReadings = 0
            delivered = false
        }
        timer.schedule(deadline: .now() + 0.15, repeating: 0.15, leeway: .milliseconds(50))
        timer.setEventHandler { [weak self] in
            guard let self, !self.delivered, let reason = self.poll(ownPID: ownPID) else { return }
            self.delivered = true
            DispatchQueue.main.async {
                MainActor.assumeIsolated { onLoss(token, reason) }
            }
        }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    /// Why the popup should close, or nil to keep watching.
    private func poll(ownPID: pid_t) -> String? {
        let launcherVisible = FocusProbe.hasLauncherWindow(ownedBy: launcherPIDs)
        if launcherVisible && !launcherWasVisible {
            return "launcher window appeared"
        }
        launcherWasVisible = launcherVisible

        // Only trust the system-wide focus once it has pointed at this panel, and
        // need two readings in a row elsewhere, so a stale answer never closes it.
        guard let pid = FocusProbe.keyboardFocusPID() else { return nil }
        if pid == ownPID {
            sawOwnFocus = true
            foreignReadings = 0
            return nil
        }
        guard sawOwnFocus else { return nil }
        foreignReadings += 1
        guard foreignReadings >= 2 else { return nil }
        let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "pid \(pid)"
        return "keyboard focus moved to \(bundleID)"
    }
}

/// Cheap checks for "something else now has the keyboard", polled while a popup is up.
enum FocusProbe {
    static let log = Logger(subsystem: "dev.roto.app", category: "popup")

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

    /// Reused rather than rebuilt on every poll. AX elements are immutable CF
    /// references and may be messaged from any thread.
    ///
    /// Never give this one a messaging timeout. Setting a timeout on the
    /// system-wide element sets it *globally for the process*, not for this
    /// object, so a short one here also applies to `AXSupport.focusedWindow()` —
    /// which then gives up on any app slower than that and reports every window
    /// command as "no accessible focused window". The poll runs off the main
    /// thread, so it can afford to wait for a slow app.
    nonisolated(unsafe) private static let system = AXUIElementCreateSystemWide()

    /// The process that owns keyboard focus right now, even for non-activating panels.
    static func keyboardFocusPID() -> pid_t? {
        guard let app = AXSupport.copy(system, kAXFocusedApplicationAttribute as String) else { return nil }
        return AXSupport.pid(of: app as! AXUIElement)
    }
}

/// Timing for the popup scale-in/out, modeled on Spotlight's panel.
@MainActor
enum PanelMotion {
    static let appearScale: CGFloat = 0.96
    static let disappearScale: CGFloat = 0.97
    static let appearFade: CFTimeInterval = 0.13
    /// The popup reaches its final size well before it finishes fading in, so it
    /// never moves once it looks solid. The spring this replaced overshot its size
    /// by half a percent and drifted back for another fifth of a second, which read
    /// as the window still settling after it had arrived.
    static let appearGrow: CFTimeInterval = 0.09
    static let disappearDuration: CFTimeInterval = 0.10

    /// Both parts of the appearance are done by then.
    static var appearDuration: CFTimeInterval { max(appearFade, appearGrow) }

    /// Reduce Motion keeps the fades and drops the scaling.
    static var scalesWindow: Bool {
        WindowScale.isAvailable && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Decelerating, and never past 1: the popup lands on its size instead of
    /// springing through it and coming back.
    static func grow(_ progress: Double) -> CGFloat {
        let p = min(max(progress, 0), 1)
        return CGFloat(1 - pow(1 - p, 4))
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
