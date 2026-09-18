import AppKit
import ServiceManagement
import RotoCore

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static var retained: AppDelegate?
    private let screens = ScreenService()
    private var statusMenu: StatusMenu!
    private var watcher: ConfigWatcher!
    private var hotkeys: HotkeyCenter!
    private var windowManager: WindowManager!
    private var navigator: WindowNavigator!
    private var launcher: AppLauncher!
    private var clipboardMonitor: ClipboardMonitor!
    private var clipboardPanel: ClipboardPanelController!
    private var emojiPanel: EmojiPanelController!
    private var windowSwitcher: WindowSwitcherController!
    private var cheatsheet: CheatsheetController!
    private var keymapEditor: KeymapEditorController!
    private var history: ClipboardHistory!
    private var catalog: EmojiCatalog!

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        retained = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        history = ClipboardHistory()
        catalog = loadCatalog()

        windowManager = WindowManager(screens: screens)
        navigator = WindowNavigator(screens: screens)
        launcher = AppLauncher()
        let images = ClipboardImageStore()
        ImageCache.store = images
        clipboardMonitor = ClipboardMonitor(history: history, images: images)
        clipboardPanel = ClipboardPanelController(history: history, monitor: clipboardMonitor)
        emojiPanel = EmojiPanelController(catalog: catalog)
        windowSwitcher = WindowSwitcherController()
        cheatsheet = CheatsheetController()
        keymapEditor = KeymapEditorController()
        hotkeys = HotkeyCenter()
        watcher = ConfigWatcher()
        statusMenu = StatusMenu()

        clipboardMonitor.onChange = { [weak self] in
            self?.clipboardPanel.historyDidChange()
        }

        cheatsheet.config = { [weak self] in
            self?.watcher.config ?? ConfigLoader.builtin
        }

        keymapEditor.onRecordingChanged = { [weak self] recording in
            self?.hotkeys.setSuspended(recording)
        }
        keymapEditor.onSaved = { [weak self] in
            self?.watcher.reload()
        }
        cheatsheet.onCustomize = { [weak self] in
            self?.showKeymapEditor()
        }
        statusMenu.onCustomizeShortcuts = { [weak self] in
            self?.showKeymapEditor()
        }
        statusMenu.onReload = { [weak self] in
            self?.watcher.reload()
        }
        statusMenu.onShowShortcuts = { [weak self] in
            self?.handle(.cheatsheet)
        }
        statusMenu.onShowWindows = { [weak self] in
            self?.handle(.windows)
        }
        statusMenu.onRequestAccessibility = {
            AXSupport.promptIfNeeded()
        }
        statusMenu.onQuit = { [weak self] in
            self?.clipboardMonitor.stop()
            self?.hotkeys = nil
        }

        hotkeys.onIssuesChanged = { [weak self] issues in
            self?.statusMenu.setShortcutIssues(issues.map(\.message))
        }
        windowManager.onIssue = { [weak self] issue in
            self?.statusMenu.setWindowIssue(issue)
        }
        hotkeys.install()
        hotkeys.onAction = { [weak self] action in
            self?.handle(action)
        }

        watcher.onChange = { [weak self] config, error in
            self?.apply(config, error: error)
        }
        watcher.start()

        clipboardMonitor.start()
        AXSupport.promptIfNeeded()
        // Answered off the main thread now, so the first popup never waits on it.
        PermissionCache.refresh()
        statusMenu.rebuild(error: watcher.errorMessage)

        // Build both popups and the emoji index now so the first hotkey press is instant.
        let catalog = catalog!
        DispatchQueue.global(qos: .utility).async {
            catalog.prepareSearch()
        }
        DispatchQueue.main.async { [weak self] in
            self?.clipboardPanel.prepare()
            self?.emojiPanel.prepare()
            self?.windowSwitcher.prepare()
            self?.cheatsheet.prepare()
        }
    }

    private func apply(_ config: Config, error: String?) {
        windowManager.gap = CGFloat(config.window.gap)
        clipboardMonitor.apply(config: config.clipboard)
        catalog.skinTone = config.emoji.skinTone
        launcher.whenFocused = config.apps.whenFocused
        clipboardPanel.popupScreen = config.general.popupScreen
        emojiPanel.popupScreen = config.general.popupScreen
        windowSwitcher.popupScreen = config.general.popupScreen
        cheatsheet.popupScreen = config.general.popupScreen
        keymapEditor.popupScreen = config.general.popupScreen
        if let bindings = try? ConfigLoader.bindings(in: config) {
            hotkeys.rebind(bindings)
        }
        statusMenu.rebuild(error: error)
        applyLaunchAtLogin(config.general.launchAtLogin)
    }

    private func applyLaunchAtLogin(_ wanted: Bool) {
        let enabled = SMAppService.mainApp.status == .enabled
        if wanted, !enabled {
            try? SMAppService.mainApp.register()
        } else if !wanted, enabled {
            try? SMAppService.mainApp.unregister()
        }
    }

    private func showKeymapEditor() {
        WindowFocus.cancelPending()
        closePopups(except: keymapEditor)
        keymapEditor.show()
    }

    private func handle(_ action: BoundAction) {
        // Ignore an already queued Carbon callback when recording has just started.
        guard !keymapEditor.isRecording else { return }
        WindowFocus.cancelPending()
        switch action {
        case .window(let command):
            switch command {
            case .focus(let direction):
                navigator.focus(direction)
            case .focusNextDisplay:
                navigator.focusAdjacentDisplay(reverse: false)
            case .focusPrevDisplay:
                navigator.focusAdjacentDisplay(reverse: true)
            default:
                windowManager.perform(command)
            }
        case .app(let target):
            launcher.toggle(target)
        case .clipboard:
            closePopups(except: clipboardPanel)
            clipboardPanel.toggle()
        case .emoji:
            closePopups(except: emojiPanel)
            emojiPanel.toggle()
        case .windows:
            closePopups(except: windowSwitcher)
            windowSwitcher.toggle()
        case .cheatsheet:
            closePopups(except: cheatsheet)
            cheatsheet.toggle()
        }
    }

    /// One popup at a time: opening one closes the others without animation.
    private func closePopups(except keep: AnyObject) {
        if keep !== clipboardPanel { clipboardPanel.dismiss(animated: false) }
        if keep !== emojiPanel { emojiPanel.dismiss(animated: false) }
        if keep !== windowSwitcher { windowSwitcher.dismiss(animated: false) }
        if keep !== cheatsheet { cheatsheet.dismiss(animated: false) }
        if keep !== keymapEditor { keymapEditor.dismiss(animated: false) }
    }

    private func loadCatalog() -> EmojiCatalog {
        let recents: [String]
        if let data = try? Data(contentsOf: Paths.emojiRecentsFile) {
            recents = EmojiCatalog.decodeRecents(from: data)
        } else {
            recents = []
        }
        let catalog: EmojiCatalog
        if let data = ResourceLoader.emojiJSON(),
           let loaded = try? EmojiCatalog.load(from: data, recents: recents) {
            catalog = loaded
        } else {
            catalog = EmojiCatalog(entries: EmojiCatalog.fallback, recents: recents)
        }
        catalog.filterGlyphs(AppleEmoji.isAvailable)
        return catalog
    }
}
