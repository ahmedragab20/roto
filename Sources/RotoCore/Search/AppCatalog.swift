import Foundation

/// An installed app the launcher can open.
public struct AppRecord: Sendable, Hashable {
    /// What Finder shows, localized and without ".app".
    public var name: String
    /// The bundle path as found, before resolving symlinks (Safari's is one).
    public var path: String
    /// `path` with symlinks resolved, as a running app reports its bundle.
    public var resolvedPath: String
    /// Other names that should find it, like the English file name of a localized app.
    public var aliases: [String]

    public init(name: String, path: String, resolvedPath: String? = nil, aliases: [String] = []) {
        self.name = name
        self.path = path
        self.resolvedPath = resolvedPath ?? path
        self.aliases = aliases
    }
}

/// Finds installed apps and names them for the fff index.
public enum AppCatalog {
    public struct Root: Sendable, Equatable {
        public var path: String
        /// 1 lists the folder's apps; 2 also lists apps in its subfolders (Utilities, vendor folders).
        public var depth: Int

        public init(_ path: String, depth: Int) {
            self.path = path
            self.depth = depth
        }
    }

    /// Where Spotlight finds apps, highest priority first: an app in /Applications
    /// wins a name it shares with a system one.
    public static var defaultRoots: [Root] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            Root("/Applications", depth: 2),
            Root("\(home)/Applications", depth: 2),
            Root("/System/Applications", depth: 2),
            Root("/System/Library/CoreServices/Applications", depth: 1),
        ]
    }

    /// Apps that live alone outside every root.
    public static let defaultExtras = ["/System/Library/CoreServices/Finder.app"]

    /// Installed apps, in root order, each bundle once even when reachable twice.
    public static func scan(roots: [Root] = defaultRoots, extras: [String] = defaultExtras) -> [AppRecord] {
        let files = FileManager.default
        var seen: Set<String> = []
        var apps: [AppRecord] = []

        func add(_ path: String) {
            let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
            guard seen.insert(resolved).inserted else { return }
            let fileName = String((path as NSString).lastPathComponent.dropLast(4))
            var name = files.displayName(atPath: path)
            if name.lowercased().hasSuffix(".app") {
                name = String(name.dropLast(4))
            }
            if name.isEmpty {
                name = fileName
            }
            apps.append(AppRecord(name: name, path: path, resolvedPath: resolved, aliases: fileName == name ? [] : [fileName]))
        }

        func walk(_ directory: String, depth: Int) {
            guard depth > 0, let names = try? files.contentsOfDirectory(atPath: directory) else { return }
            var folders: [String] = []
            for name in names.sorted() where !name.hasPrefix(".") {
                let path = (directory as NSString).appendingPathComponent(name)
                if name.lowercased().hasSuffix(".app") {
                    add(path)
                } else if depth > 1 {
                    folders.append(path)
                }
            }
            // A folder's own apps come before the ones in its subfolders.
            for folder in folders {
                var isDirectory: ObjCBool = false
                if files.fileExists(atPath: folder, isDirectory: &isDirectory), isDirectory.boolValue {
                    walk(folder, depth: depth - 1)
                }
            }
        }

        for root in roots {
            walk(root.path, depth: root.depth)
        }
        for path in extras where files.fileExists(atPath: path) {
            add(path)
        }
        return apps
    }

    /// The index file name for every searchable name, mapped to its app's
    /// position in `apps`. An earlier app keeps a name both share; names that
    /// differ only in case are one name, as they are on a Mac disk.
    public static func indexNames(for apps: [AppRecord]) -> [String: Int] {
        var names: [String: Int] = [:]
        var taken: Set<String> = []
        for (position, app) in apps.enumerated() {
            for name in [app.name] + app.aliases {
                guard let fileName = indexFileName(name), taken.insert(fileName.lowercased()).inserted else { continue }
                names[fileName] = position
            }
        }
        return names
    }

    /// `name` as a plain file name: no path separators, nothing hidden, never empty.
    public static func indexFileName(_ name: String) -> String? {
        let cleaned = name
            .replacingOccurrences(of: "/", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let visible = String(cleaned.drop { $0 == "." })
        guard !visible.isEmpty, visible.utf8.count <= 255 else { return nil }
        return visible
    }
}
