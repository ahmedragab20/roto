import AppKit
import os
import RotoCore

@MainActor
final class AppLauncher {
    var whenFocused: AppFocusBehavior = .cycle
    private let log = Logger(subsystem: "dev.roto.app", category: "apps")

    /// `target` is a bundle id (`com.mitchellh.ghostty`), an app name (`Ghostty`),
    /// or a path to an `.app`.
    func toggle(_ target: String) {
        let target = target.trimmingCharacters(in: .whitespacesAndNewlines)
        if let app = runningApp(for: target) {
            handleRunning(app)
        } else if let url = appURL(for: target) {
            WindowFocus.open(url)
        } else {
            log.error("no installed app matches '\(target, privacy: .public)'")
            NSSound.beep()
        }
    }

    private func handleRunning(_ app: NSRunningApplication) {
        let isFront = NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
        let windows = visibleWindows(of: app)

        guard isFront, !app.isHidden else {
            if windows.isEmpty, let url = app.bundleURL {
                // Nothing to show here: like a Dock click, restore a minimized
                // window, jump to its Space, or open a new window.
                WindowFocus.open(url)
            } else {
                WindowFocus.activate(app)
            }
            return
        }

        switch whenFocused {
        case .cycle:
            // Raising the backmost window each time walks through all of them.
            guard windows.count > 1, let back = windows.last else { return }
            WindowFocus.focus(back.ref.element, pid: app.processIdentifier)
        case .hide:
            app.hide()
        case .nothing:
            break
        }
    }

    private func visibleWindows(of app: NSRunningApplication) -> [(entry: WindowEntry, ref: AXWindowRef)] {
        let info = RunningAppInfo(
            pid: app.processIdentifier,
            name: app.localizedName ?? "",
            bundleID: app.bundleIdentifier,
            isHidden: app.isHidden,
            isFrontmost: false
        )
        return WindowCatalog.windows(of: info).filter { !$0.entry.isMinimized && $0.entry.stackOrder != nil }
    }

    private func runningApp(for target: String) -> NSRunningApplication? {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: target).first {
            return app
        }
        let path = expandedAppPath(target)
        let name = appName(target)
        return NSWorkspace.shared.runningApplications.first { app in
            guard app.activationPolicy != .prohibited else { return false }
            if let path, app.bundleURL?.standardizedFileURL.path == path { return true }
            if app.localizedName?.lowercased() == name { return true }
            return app.bundleURL?.deletingPathExtension().lastPathComponent.lowercased() == name
        }
    }

    private func appURL(for target: String) -> URL? {
        if let path = expandedAppPath(target), FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target) {
            return url
        }
        let wanted = appName(target) + ".app"
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let bases = [
            "/Applications",
            "/Applications/Utilities",
            "\(home)/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
        ]
        for base in bases {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: base)) ?? []
            if let match = names.first(where: { $0.lowercased() == wanted }) {
                return URL(fileURLWithPath: base).appendingPathComponent(match)
            }
        }
        return nil
    }

    private func expandedAppPath(_ target: String) -> String? {
        guard target.hasPrefix("/") || target.hasPrefix("~") else { return nil }
        return URL(fileURLWithPath: (target as NSString).expandingTildeInPath).standardizedFileURL.path
    }

    private func appName(_ target: String) -> String {
        let last = (target as NSString).lastPathComponent
        let name = last.lowercased().hasSuffix(".app") ? String(last.dropLast(4)) : last
        return name.lowercased()
    }
}
