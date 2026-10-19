import AppKit
import SwiftUI
import Testing
import RotoCore
@testable import Roto

@MainActor
struct LauncherControllerTests {
    private func fixture() async throws -> (URL, AppSearch) {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("roto-launcher-\(UUID().uuidString)")
        for name in ["Safari", "Sleepy"] {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("Apps/\(name).app"), withIntermediateDirectories: true
            )
        }
        let search = AppSearch(
            directory: root.appendingPathComponent("index"), frecencyDirectory: nil,
            roots: [.init(root.appendingPathComponent("Apps").path, depth: 1)], extras: []
        )
        _ = await Task.detached { search.refreshNow() }.value
        return (root, search)
    }

    private func key(_ code: UInt16, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
            windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
            isARepeat: false, keyCode: code
        )!
    }

    @Test func typingAndFinderShortcutNeverExecuteACommandButReturnDoes() async throws {
        let (root, search) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var executed: [LauncherCommand] = []
        let controller = LauncherController(search: search) { executed.append($0) }
        controller.query = "sleep"
        #expect(controller.results.map(\.name) == ["Sleep Display", "Sleepy"])
        #expect(executed.isEmpty)
        #expect(controller.selectedApp == nil)
        #expect(controller.hints.map(\.label) == ["Run", "Choose result"])
        #expect(controller.handleKey(key(PanelKey.returnKey, modifiers: .command)))
        #expect(executed.isEmpty)
        #expect(controller.handleKey(key(PanelKey.returnKey)))
        #expect(executed == [.sleepDisplay])
    }

    @Test func navigationAndNumberShortcutsUseTheMixedResultOrder() async throws {
        let (root, search) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var executed: [LauncherCommand] = []
        let controller = LauncherController(search: search) { executed.append($0) }
        controller.apply(commands: [.sleepDisplay])
        #expect(controller.results.map(\.name) == ["Safari", "Sleepy", "Sleep Display"])
        #expect(controller.status == "2 apps · 1 command")
        #expect(controller.hints.map(\.label) == ["Open", "Show in Finder", "Choose result"])
        #expect(controller.handleKey(key(PanelKey.end)))
        #expect(controller.selectedResult == .command(.sleepDisplay))
        #expect(controller.handleKey(key(PanelKey.up)))
        #expect(controller.selectedApp?.name == "Sleepy")
        // Physical key code 20 is the 3 key, choosing the command after two apps.
        #expect(controller.handleKey(key(20, modifiers: .command)))
        #expect(executed == [.sleepDisplay])
    }

    @Test func configReloadPreservesSelectionAndRemovedCommandsCannotRun() async throws {
        let (root, search) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var executed: [LauncherCommand] = []
        let controller = LauncherController(search: search) { executed.append($0) }
        let original = LauncherCommand(name: "Task", command: "original")
        controller.apply(commands: [original])
        controller.query = "task"
        #expect(controller.selectedResult == .command(original))
        let replacement = LauncherCommand(name: "Task", command: "replacement")
        controller.apply(commands: [LauncherCommand(name: "Task Extra", command: "other"), replacement])
        #expect(controller.selectedResult == .command(replacement))
        controller.open(at: controller.selection)
        #expect(executed == [replacement])

        controller.apply(commands: [])
        #expect(controller.results.isEmpty)
        #expect(controller.selection == 0)
        controller.open(at: 0)
        controller.open(at: -1)
        #expect(executed == [replacement])
    }

    @Test func searchTextIsNeverTreatedAsShellInput() async throws {
        let (root, search) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var executed: [LauncherCommand] = []
        let controller = LauncherController(search: search) { executed.append($0) }
        controller.query = "sleep; echo should-not-run"
        #expect(controller.results.isEmpty)
        #expect(controller.handleKey(key(PanelKey.returnKey)))
        #expect(executed.isEmpty)
    }

    @Test func mixedResultsAndEmptyStateStayWithinThePopup() async throws {
        let (root, search) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = LauncherController(search: search) { _ in Issue.record("Rendering must not run commands") }
        let size = NSSize(width: 680, height: 460)
        let panel = FloatingPanel(size: size)
        let host = NSHostingView(rootView: LauncherView(model: controller).background(Color(nsColor: .windowBackgroundColor)))
        host.appearance = NSAppearance(named: .aqua)
        panel.embed(rootView: host)
        for (state, query) in [("mixed", "sleep"), ("apps", "safari"), ("empty", "no-such-result")] {
            controller.query = query
            host.invalidateIntrinsicContentSize()
            panel.contentView?.layoutSubtreeIfNeeded()
            panel.layoutIfNeeded()
            #expect(host.frame.size == size)
            #expect(host.fittingSize.width <= size.width)
            #expect(host.fittingSize.height <= size.height)

            // Optional native renders for manual visual inspection, kept out of the repo.
            if let directory = ProcessInfo.processInfo.environment["ROTO_LAUNCHER_PREVIEW_DIR"] {
                let url = URL(fileURLWithPath: directory).appendingPathComponent("launcher-\(state).png")
                let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try #require(bitmap.representation(using: .png, properties: [:])).write(to: url)
            }
        }
    }
}
