import Foundation
import Testing
@testable import RotoCore

struct WindowListTests {
    private func window(
        _ id: String,
        app: String = "App",
        title: String = "",
        stack: Int? = nil,
        focused: Bool = false,
        minimized: Bool = false,
        hidden: Bool = false,
        appOnly: Bool = false
    ) -> WindowEntry {
        WindowEntry(
            id: id,
            pid: 1,
            appName: app,
            title: title,
            isMinimized: minimized,
            isAppHidden: hidden,
            isFocused: focused,
            isAppOnly: appOnly,
            stackOrder: stack
        )
    }

    @Test func sortsFocusedThenStackThenOffscreenMinimizedHiddenAppOnly() {
        let input = [
            window("appOnly", app: "Finder", appOnly: true),
            window("min", minimized: true),
            window("back", stack: 3),
            window("hidden", hidden: true),
            window("front", stack: 1),
            window("current", stack: 0, focused: true),
            window("offscreen"),
        ]
        #expect(WindowList.sorted(input).map(\.id) == [
            "current", "front", "back", "offscreen", "min", "hidden", "appOnly",
        ])
    }

    @Test func initialSelectionSkipsCurrentWindow() {
        let withCurrent = [window("current", stack: 0, focused: true), window("front", stack: 1)]
        #expect(WindowList.initialSelection(withCurrent, query: "") == 1)
        #expect(WindowList.initialSelection(withCurrent, query: "x") == 0)
        let onlyCurrent = [window("current", stack: 0, focused: true)]
        #expect(WindowList.initialSelection(onlyCurrent, query: "") == 0)
        let noCurrent = [window("front", stack: 1), window("back", stack: 2)]
        #expect(WindowList.initialSelection(noCurrent, query: "") == 0)
    }

    @Test func filterMatchesTitleAndAppName() {
        let entries = [
            window("a", app: "Helium", title: "GitHub - roto"),
            window("b", app: "Ghostty", title: "zsh"),
            window("c", app: "Notes", title: "Helium ideas"),
        ]
        #expect(WindowList.filtered(entries, query: "helium").map(\.id) == ["a", "c"])
        #expect(WindowList.filtered(entries, query: "zsh").map(\.id) == ["b"])
        #expect(WindowList.filtered(entries, query: "").count == 3)
    }
}
