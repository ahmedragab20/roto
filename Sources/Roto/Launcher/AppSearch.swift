import Foundation
import os
import RotoCore

/// Installed apps, searched with fff.
///
/// Scanning and index upkeep run on a background queue; `search` is cheap
/// enough (well under a millisecond for a few hundred apps) to answer on the
/// main thread, in the same frame as the keystroke.
final class AppSearch: @unchecked Sendable {
    private let queue = DispatchQueue(label: "roto.apps", qos: .userInitiated)
    private let log = Logger(subsystem: "dev.roto.app", category: "apps")
    private let directory: URL
    private let frecencyDirectory: URL?
    private let roots: [AppCatalog.Root]
    private let extras: [String]

    /// Guards the three below; `search` reads them from the main thread.
    private let lock = NSLock()
    private var apps: [AppRecord] = []
    private var names: [String: Int] = [:]
    private var index: FFFIndex?
    /// Only touched on `queue`.
    private var triedIndex = false

    init(
        directory: URL = Paths.appIndexDirectory,
        frecencyDirectory: URL? = Paths.appFrecencyDirectory,
        roots: [AppCatalog.Root] = AppCatalog.defaultRoots,
        extras: [String] = AppCatalog.defaultExtras
    ) {
        self.directory = directory
        self.frecencyDirectory = frecencyDirectory
        self.roots = roots
        self.extras = extras
    }

    var count: Int {
        lock.withLock { apps.count }
    }

    /// Rescans the app folders and brings the index up to date. `completion`
    /// runs on the main thread and says whether the app list changed.
    func refresh(completion: (@MainActor @Sendable (Bool) -> Void)? = nil) {
        queue.async { [self] in
            let changed = refreshNow()
            guard let completion else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { completion(changed) }
            }
        }
    }

    /// Blocks until a scan finishes; for tests and `refresh`.
    @discardableResult
    func refreshNow() -> Bool {
        dispatchPrecondition(condition: .notOnQueue(.main))
        let scanned = AppCatalog.scan(roots: roots, extras: extras)
        let wanted = AppCatalog.indexNames(for: scanned)
        let diskChanged = sync(Set(wanted.keys))

        var index = lock.withLock { self.index }
        if index == nil, !triedIndex {
            triedIndex = true
            index = FFFIndex(directory: directory, frecencyDirectory: frecencyDirectory)
            if index == nil {
                log.error("fff could not open \(self.directory.path, privacy: .public); using the built-in matcher")
            }
            index?.rescan(full: false)
        } else if diskChanged {
            index?.rescan(full: true)
        }

        return lock.withLock {
            let changed = scanned != apps
            apps = scanned
            names = wanted
            self.index = index
            return changed
        }
    }

    /// Best match first. An empty query lists every app, recently opened ones first.
    func search(_ query: String, limit: Int) -> [AppRecord] {
        let (apps, names, index) = lock.withLock { (self.apps, self.names, self.index) }
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index else {
            return Array(fallback(query, apps: apps).prefix(limit))
        }

        // Aliases can return one app twice, so ask for a few more than shown.
        let shown = min(limit, names.count)
        let matches = index.search(query, limit: query.isEmpty ? names.count : shown + shown / 2)
        var seen: Set<Int> = []
        var result: [AppRecord] = []
        result.reserveCapacity(min(limit, matches.count))
        for match in matches where !query.isEmpty || match.score > 0 {
            guard let position = names[match.name], seen.insert(position).inserted else { continue }
            result.append(apps[position])
            if result.count == limit { return result }
        }
        if query.isEmpty {
            let rest = apps.indices
                .filter { !seen.contains($0) }
                .map { apps[$0] }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            result += rest.prefix(limit - result.count)
        }
        return result
    }

    /// Ranks `app` higher from now on.
    func recordLaunch(_ app: AppRecord) {
        queue.async { [self] in
            let (apps, names, index) = lock.withLock { (self.apps, self.names, self.index) }
            guard let index else { return }
            // Every name it can be found by, so a search for either ranks it higher.
            for name in [app.name] + app.aliases {
                guard let fileName = AppCatalog.indexFileName(name),
                      let position = names[fileName], apps[position].path == app.path
                else { continue }
                index.track(fileName)
            }
        }
    }

    /// Returns once queued work (a refresh, a recorded launch) has finished.
    func waitUntilIdle() {
        queue.sync {}
    }

    /// Makes the index directory hold exactly `wanted`. Reports whether it changed.
    private func sync(_ wanted: Set<String>) -> Bool {
        let files = FileManager.default
        try? files.createDirectory(at: directory, withIntermediateDirectories: true)
        let existing = Set((try? files.contentsOfDirectory(atPath: directory.path)) ?? [])
        var changed = false
        for name in existing.subtracting(wanted) {
            try? files.removeItem(at: directory.appendingPathComponent(name))
            changed = true
        }
        for name in wanted.subtracting(existing) {
            files.createFile(atPath: directory.appendingPathComponent(name).path, contents: nil)
            changed = true
        }
        return changed
    }

    /// Used only when fff could not open its index.
    private func fallback(_ query: String, apps: [AppRecord]) -> [AppRecord] {
        guard !query.isEmpty else {
            return apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        return Fuzzy.ranked(apps, query: query) { [$0.name] + $0.aliases }
    }
}
