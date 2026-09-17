import AppKit
import Testing
@testable import Roto

@MainActor
struct StatusMenuTests {
    @Test func rechecksAccessibilityWhenOpeningMenu() throws {
        _ = NSApplication.shared
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(item) }
        var trusted = false
        let controller = StatusMenu(statusItem: item, accessibilityStatus: { trusted })
        let menu = try #require(item.menu)
        let access = try #require(menu.items.first)
        #expect(access.title == "Accessibility: needed — click to grant")
        #expect(access.isEnabled)

        let delegate = try #require(menu.delegate)
        #expect(delegate === controller)
        trusted = true
        delegate.menuNeedsUpdate?(menu)
        #expect(access.title == "Accessibility: granted")
        #expect(!access.isEnabled)
        #expect(item.menu === menu)

        trusted = false
        delegate.menuNeedsUpdate?(menu)
        #expect(access.title == "Accessibility: needed — click to grant")
        #expect(access.isEnabled)
    }

    @Test func rebuiltMenuStillRefreshesWithoutChangingOtherItems() throws {
        _ = NSApplication.shared
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(item) }
        var trusted = true
        let controller = StatusMenu(statusItem: item, accessibilityStatus: { trusted })
        controller.rebuild(error: "Example config error")
        let menu = try #require(item.menu)
        let access = try #require(menu.items.first)
        #expect(access.title == "Accessibility: granted")
        #expect(!access.isEnabled)
        let remainingTitles = menu.items.dropFirst().map(\.title)
        #expect(remainingTitles.contains("Config error: Example config error"))

        let delegate = try #require(menu.delegate)
        #expect(delegate === controller)
        trusted = false
        delegate.menuNeedsUpdate?(menu)
        #expect(access.title == "Accessibility: needed — click to grant")
        #expect(access.isEnabled)
        #expect(menu.items.dropFirst().map(\.title) == remainingTitles)
        #expect(item.menu === menu)
    }
}
