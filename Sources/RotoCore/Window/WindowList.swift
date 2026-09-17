import CoreGraphics
import Foundation

public struct WindowEntry: Sendable, Equatable, Identifiable {
    public var id: String
    public var pid: Int32
    public var appName: String
    public var bundleID: String?
    public var title: String
    public var windowID: UInt32?
    /// Accessibility coordinates (origin at the top-left of the primary display).
    public var frame: CGRect?
    public var isMinimized: Bool
    public var isAppHidden: Bool
    public var isFullScreen: Bool
    public var isFocused: Bool
    /// A running app with no window reachable on this Space.
    public var isAppOnly: Bool
    /// Front-to-back position among on-screen windows; nil when not on screen.
    public var stackOrder: Int?

    public init(
        id: String,
        pid: Int32,
        appName: String,
        bundleID: String? = nil,
        title: String = "",
        windowID: UInt32? = nil,
        frame: CGRect? = nil,
        isMinimized: Bool = false,
        isAppHidden: Bool = false,
        isFullScreen: Bool = false,
        isFocused: Bool = false,
        isAppOnly: Bool = false,
        stackOrder: Int? = nil
    ) {
        self.id = id
        self.pid = pid
        self.appName = appName
        self.bundleID = bundleID
        self.title = title
        self.windowID = windowID
        self.frame = frame
        self.isMinimized = isMinimized
        self.isAppHidden = isAppHidden
        self.isFullScreen = isFullScreen
        self.isFocused = isFocused
        self.isAppOnly = isAppOnly
        self.stackOrder = stackOrder
    }
}

public enum WindowList {
    /// Focused window first, then on-screen windows front to back, then windows
    /// off screen, minimized, in hidden apps, and apps with no reachable window.
    public static func sorted(_ entries: [WindowEntry]) -> [WindowEntry] {
        entries.enumerated()
            .sorted { lhs, rhs in
                let a = sortKey(lhs.element)
                let b = sortKey(rhs.element)
                if a.group != b.group { return a.group < b.group }
                if a.stack != b.stack { return a.stack < b.stack }
                if a.app != b.app { return a.app < b.app }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    /// Matches on title and app name. Strong matches first; otherwise keeps `entries` order.
    public static func filtered(_ entries: [WindowEntry], query: String) -> [WindowEntry] {
        let prepared = SearchQuery(query)
        if prepared.isEmpty { return entries }
        return entries.enumerated()
            .compactMap { offset, entry -> (band: Int, offset: Int, entry: WindowEntry)? in
                let fields = [
                    SearchField(entry.title),
                    SearchField(entry.appName, weight: 0.9, isPrimary: false),
                ]
                guard let score = Fuzzy.score(prepared, fields: fields) else { return nil }
                let band = score >= 75 ? 2 : (score >= 45 ? 1 : 0)
                return (band, offset, entry)
            }
            .sorted { $0.band != $1.band ? $0.band > $1.band : $0.offset < $1.offset }
            .map(\.entry)
    }

    /// With no search, preselect the window behind the current one so ↩ flips back, like ⌘⇥.
    public static func initialSelection(_ entries: [WindowEntry], query: String) -> Int {
        guard SearchQuery(query).isEmpty, entries.count > 1, entries[0].isFocused else { return 0 }
        return 1
    }

    private static func sortKey(_ entry: WindowEntry) -> (group: Int, stack: Int, app: String) {
        let group: Int
        if entry.isFocused {
            group = 0
        } else if entry.isAppOnly {
            group = 5
        } else if entry.isAppHidden {
            group = 4
        } else if entry.isMinimized {
            group = 3
        } else if entry.stackOrder == nil {
            group = 2
        } else {
            group = 1
        }
        return (group, entry.stackOrder ?? Int.max, entry.appName.lowercased())
    }
}
