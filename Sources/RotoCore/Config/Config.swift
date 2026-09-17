import Foundation

public struct FractionalRect: Sendable, Equatable, Codable {
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double

    public init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }
}

public struct Config: Sendable, Equatable {
    public var general: General
    public var window: Window
    public var hotkeys: Hotkeys
    public var apps: Apps
    public var clipboard: Clipboard
    public var emoji: Emoji

    public struct General: Sendable, Equatable {
        public var launchAtLogin: Bool
        public var popupScreen: PopupScreen
        public init(launchAtLogin: Bool = false, popupScreen: PopupScreen = .primary) {
            self.launchAtLogin = launchAtLogin
            self.popupScreen = popupScreen
        }
    }

    public struct Window: Sendable, Equatable {
        public var gap: Double
        public var layouts: [String: FractionalRect]
        public init(gap: Double = 0, layouts: [String: FractionalRect] = [:]) {
            self.gap = gap
            self.layouts = layouts
        }
    }

    public struct Hotkeys: Sendable, Equatable {
        public var window: [String: String]
        public var apps: [String: String]
        public var clipboard: String?
        public var emoji: String?
        public var windows: String?
        public var cheatsheet: String?
        public init(
            window: [String: String] = [:],
            apps: [String: String] = [:],
            clipboard: String? = nil,
            emoji: String? = nil,
            windows: String? = nil,
            cheatsheet: String? = nil
        ) {
            self.window = window
            self.apps = apps
            self.clipboard = clipboard
            self.emoji = emoji
            self.windows = windows
            self.cheatsheet = cheatsheet
        }
    }

    public struct Apps: Sendable, Equatable {
        /// What an app hotkey does when that app is already in front.
        public var whenFocused: AppFocusBehavior
        public init(whenFocused: AppFocusBehavior = .cycle) {
            self.whenFocused = whenFocused
        }
    }

    public struct Clipboard: Sendable, Equatable {
        public var historySize: Int
        /// Entries last copied longer ago than this are dropped; 0 keeps them forever.
        public var maxAgeDays: Int
        public var persist: Bool
        public var includeImages: Bool
        public var ignoreApps: [String]
        public init(
            historySize: Int = 200,
            maxAgeDays: Int = 60,
            persist: Bool = true,
            includeImages: Bool = true,
            ignoreApps: [String] = ["com.1password.1password"]
        ) {
            self.historySize = historySize
            self.maxAgeDays = maxAgeDays
            self.persist = persist
            self.includeImages = includeImages
            self.ignoreApps = ignoreApps
        }
    }

    public struct Emoji: Sendable, Equatable {
        public var skinTone: String
        public init(skinTone: String = "default") {
            self.skinTone = skinTone
        }
    }

    public init(
        general: General = General(),
        window: Window = Window(),
        hotkeys: Hotkeys = Hotkeys(),
        apps: Apps = Apps(),
        clipboard: Clipboard = Clipboard(),
        emoji: Emoji = Emoji()
    ) {
        self.general = general
        self.window = window
        self.hotkeys = hotkeys
        self.apps = apps
        self.clipboard = clipboard
        self.emoji = emoji
    }
}

public enum PopupScreen: String, Sendable, CaseIterable {
    case primary
    case cursor
    case frontmost
}

public enum AppFocusBehavior: String, Sendable, CaseIterable {
    /// Bring the app's next window forward.
    case cycle
    /// Hide the app, like ⌘H.
    case hide
    /// Leave it as is.
    case nothing = "none"
}

public enum SkinTone: String, Sendable, CaseIterable {
    case `default`
    case light
    case mediumLight = "medium-light"
    case medium
    case mediumDark = "medium-dark"
    case dark
}

public enum Paths {
    public static var configDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("roto", isDirectory: true)
    }

    public static var configFile: URL {
        configDirectory.appendingPathComponent("config.toml")
    }

    public static var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("roto", isDirectory: true)
    }

    public static var clipboardFile: URL {
        supportDirectory.appendingPathComponent("clipboard.json")
    }

    public static var clipboardImagesDirectory: URL {
        supportDirectory.appendingPathComponent("clipboard-images", isDirectory: true)
    }

    public static var emojiRecentsFile: URL {
        supportDirectory.appendingPathComponent("emoji-recents.json")
    }
}
