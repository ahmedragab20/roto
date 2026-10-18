import CFFFBridge
import Foundation

/// An fff index over the names in one directory (see native/fff-bridge).
///
/// fff matches file names, so the launcher writes one empty file per app and
/// asks fff which names match. Searches may run on any thread; fff guards its
/// index with a reader-writer lock.
final class FFFIndex: @unchecked Sendable {
    struct Match: Equatable {
        let name: String
        let score: Int32
    }

    private let handle: OpaquePointer

    /// `frecencyDirectory` holds fff's launch history; nil keeps none.
    init?(directory: URL, frecencyDirectory: URL?) {
        guard let handle = fff_bridge_open(directory.path, frecencyDirectory?.path) else { return nil }
        self.handle = handle
    }

    deinit {
        fff_bridge_close(handle)
    }

    /// Waits for the scan in progress; with `full`, rescans the directory first.
    @discardableResult
    func rescan(full: Bool, timeout: TimeInterval = 2) -> Bool {
        fff_bridge_rescan(handle, UInt64(timeout * 1000), full)
    }

    /// Best first. An empty query lists every name, most used first.
    func search(_ query: String, limit: Int) -> [Match] {
        final class Sink {
            var matches: [Match] = []
        }
        let sink = Sink()
        sink.matches.reserveCapacity(min(limit, 64))
        withExtendedLifetime(sink) {
            _ = fff_bridge_search(handle, query, UInt32(clamping: limit), { name, score, context in
                guard let name, let context else { return }
                let sink = Unmanaged<Sink>.fromOpaque(context).takeUnretainedValue()
                sink.matches.append(Match(name: String(cString: name), score: score))
            }, Unmanaged.passUnretained(sink).toOpaque())
        }
        return sink.matches
    }

    /// Records a launch so `name` ranks higher from now on.
    @discardableResult
    func track(_ name: String) -> Bool {
        fff_bridge_track(handle, name)
    }
}
