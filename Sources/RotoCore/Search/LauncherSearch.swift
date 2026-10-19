import Foundation

/// A named shell command from the user's config. Search text is never executed.
public struct LauncherCommand: Sendable, Equatable {
    public var name: String
    public var command: String
    public var keywords: [String]

    public init(name: String, command: String, keywords: [String] = []) {
        self.name = name
        self.command = command
        self.keywords = keywords
    }

    public static let sleepDisplay = LauncherCommand(
        name: "Sleep Display",
        command: "/usr/bin/pmset displaysleepnow",
        keywords: ["sleep", "screen off", "display off", "monitor off"]
    )
}

public enum LauncherResult: Sendable, Equatable, Identifiable {
    case app(AppRecord)
    case command(LauncherCommand)

    public var id: String {
        switch self {
        case .app(let app): "app:\(app.path)"
        case .command(let command): "command:\(Fuzzy.normalize(command.name))"
        }
    }

    public var name: String {
        switch self {
        case .app(let app): app.name
        case .command(let command): command.name
        }
    }
}

public enum LauncherSearch {
    /// Keep fff's app ordering and learned preferences. Insert commands after all
    /// equally strong app matches; keywords carry less weight than names.
    public static func merge(
        apps: [AppRecord], commands: [LauncherCommand], query: String, limit: Int
    ) -> [LauncherResult] {
        guard limit > 0 else { return [] }
        let prepared = SearchQuery(query)
        if prepared.isEmpty {
            return Array((apps.map(LauncherResult.app) + commands.map(LauncherResult.command)).prefix(limit))
        }

        let matches = commands.enumerated().compactMap { offset, command -> (Int, Int, LauncherCommand)? in
            let fields = [SearchField(command.name)] + command.keywords.map {
                SearchField($0, weight: 0.85, minimumTokenLength: 2, isPrimary: false)
            }
            guard let score = Fuzzy.score(prepared, fields: fields) else { return nil }
            return (Fuzzy.rankKey(score), offset, command)
        }.sorted { $0.0 != $1.0 ? $0.0 > $1.0 : $0.1 < $1.1 }
        guard !matches.isEmpty else { return apps.prefix(limit).map(LauncherResult.app) }

        // A later exact app match must not be overtaken because fff put a
        // frequently used, weaker match before it.
        var remainingScores = Array(repeating: 0, count: apps.count + 1)
        for index in apps.indices.reversed() {
            let score = Fuzzy.score(prepared, fields: ([apps[index].name] + apps[index].aliases).map { SearchField($0) }) ?? 0
            remainingScores[index] = max(remainingScores[index + 1], Fuzzy.rankKey(score))
        }
        var result: [LauncherResult] = []
        var next = 0
        for index in 0...apps.count {
            while next < matches.count, matches[next].0 > remainingScores[index] {
                result.append(.command(matches[next].2))
                next += 1
            }
            if index < apps.count { result.append(.app(apps[index])) }
        }
        return Array(result.prefix(limit))
    }
}
