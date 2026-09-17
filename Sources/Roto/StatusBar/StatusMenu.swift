import AppKit
import ServiceManagement
import RotoCore

@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private let item: NSStatusItem
    private let accessibilityStatus: () -> Bool
    var onReload: (() -> Void)?
    var onShowShortcuts: (() -> Void)?
    var onCustomizeShortcuts: (() -> Void)?
    var onShowWindows: (() -> Void)?
    var onQuit: (() -> Void)?
    var onRequestAccessibility: (() -> Void)?
    private var lastError: String?
    private var shortcutIssues: [String] = []
    private var lastWindowIssue: String?

    init(
        statusItem: NSStatusItem? = nil,
        accessibilityStatus: @escaping () -> Bool = { AXSupport.isTrusted }
    ) {
        item = statusItem ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.accessibilityStatus = accessibilityStatus
        super.init()
        item.button?.image = Self.markImage
        item.menu = NSMenu()
        rebuild(error: nil)
    }

    func setShortcutIssues(_ issues: [String]) {
        guard issues != shortcutIssues else { return }
        shortcutIssues = issues
        rebuild(error: lastError)
    }

    func setWindowIssue(_ issue: String?) {
        guard issue != lastWindowIssue else { return }
        lastWindowIssue = issue
        rebuild(error: lastError)
    }

    func rebuild(error: String?) {
        lastError = error
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        let access = NSMenuItem(
            title: "",
            action: #selector(grantAccess),
            keyEquivalent: ""
        )
        access.target = self
        menu.addItem(access)
        menuNeedsUpdate(menu)

        var warnings = shortcutIssues
        if let error, !error.isEmpty { warnings.insert("Config error: \(error)", at: 0) }
        if let lastWindowIssue { warnings.append("Last window action: \(lastWindowIssue)") }
        for warning in warnings {
            let entry = NSMenuItem(title: warning, action: nil, keyEquivalent: "")
            entry.isEnabled = false
            menu.addItem(entry)
        }
        if warnings.isEmpty {
            item.button?.image = Self.markImage
        } else if let button = item.button {
            button.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "roto needs attention")
            button.image?.isTemplate = true
        }

        menu.addItem(.separator())

        let shortcuts = NSMenuItem(title: "Keyboard Shortcuts…", action: #selector(showShortcuts), keyEquivalent: "/")
        shortcuts.target = self
        menu.addItem(shortcuts)

        let customize = NSMenuItem(title: "Customize Shortcuts…", action: #selector(customizeShortcuts), keyEquivalent: ",")
        customize.target = self
        menu.addItem(customize)

        let windows = NSMenuItem(title: "Switch Windows…", action: #selector(showWindows), keyEquivalent: "")
        windows.target = self
        menu.addItem(windows)

        menu.addItem(.separator())

        let reload = NSMenuItem(title: "Reload config", action: #selector(reload), keyEquivalent: "r")
        reload.target = self
        menu.addItem(reload)

        let open = NSMenuItem(title: "Open config…", action: #selector(openConfig), keyEquivalent: "o")
        open.target = self
        menu.addItem(open)

        let login = NSMenuItem(title: "Launch at login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = loginEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit roto", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let access = menu.items.first(where: { $0.action == #selector(grantAccess) }) else { return }
        // Permission can change in System Settings without any config change or app activation.
        let trusted = accessibilityStatus()
        access.title = trusted ? "Accessibility: granted" : "Accessibility: needed — click to grant"
        access.isEnabled = !trusted
    }

    /// The roto mark as a template, so macOS tints it like any menu bar icon.
    private static let markImage: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.addPath(BrandMark.path(in: rect.insetBy(dx: 1.5, dy: 1.5), gap: 0.08, cornerRatio: 0.28))
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "roto"
        return image
    }()

    private var loginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @objc private func grantAccess() {
        onRequestAccessibility?()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        rebuild(error: lastError)
    }

    @objc private func showShortcuts() {
        onShowShortcuts?()
    }

    @objc private func customizeShortcuts() {
        onCustomizeShortcuts?()
    }

    @objc private func showWindows() {
        onShowWindows?()
    }

    @objc private func reload() {
        onReload?()
    }

    @objc private func openConfig() {
        NSWorkspace.shared.open(Paths.configFile)
    }

    @objc private func toggleLogin() {
        do {
            if loginEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Launch at login"
            alert.informativeText = error.localizedDescription + "\n\nInstall roto to /Applications (make install) for login items to work."
            alert.runModal()
        }
        rebuild(error: lastError)
    }

    @objc private func quit() {
        onQuit?()
        NSApp.terminate(nil)
    }
}
