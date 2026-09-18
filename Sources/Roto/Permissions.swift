import AppKit
import ApplicationServices

/// What macOS currently lets roto do.
struct Permissions: Equatable, Sendable {
    /// Synthetic ⌘V and typed glyphs will land.
    var canPostEvents: Bool
    /// Window previews can be captured.
    var canCaptureScreen: Bool
}

/// The last known answers to the permission questions a popup asks as it opens.
///
/// `CGPreflightPostEventAccess` and `CGPreflightScreenCaptureAccess` each take a
/// synchronous round trip to the permission daemon — about 6 ms measured, every
/// call, with no caching of their own. Asking during `show()` spent most of a
/// frame before the window was ever ordered in, so the answers are kept here and
/// re-read off the main thread instead.
@MainActor
enum PermissionCache {
    /// Accessibility trust is a cheap in-process check and post-event access
    /// follows it, so the first answer is already right in practice.
    private(set) static var current = Permissions(
        canPostEvents: AXIsProcessTrusted(),
        canCaptureScreen: false
    )

    private static let queue = DispatchQueue(label: "roto.permissions", qos: .userInitiated)
    private static var refreshing = false
    private static var pending: [@MainActor (Permissions) -> Void] = []

    /// Re-reads both permissions off the main thread. `changed` runs on the main
    /// thread afterwards, only when an answer is different from the cached one,
    /// so a popup can drop its banner mid-showing without ever blocking to ask.
    static func refresh(_ changed: (@MainActor (Permissions) -> Void)? = nil) {
        if let changed {
            pending.append(changed)
        }
        guard !refreshing else { return }
        refreshing = true
        queue.async {
            let fresh = Permissions(
                canPostEvents: CGPreflightPostEventAccess() || AXIsProcessTrusted(),
                canCaptureScreen: CGPreflightScreenCaptureAccess()
            )
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    refreshing = false
                    let callbacks = pending
                    pending = []
                    guard fresh != current else { return }
                    current = fresh
                    for callback in callbacks {
                        callback(fresh)
                    }
                }
            }
        }
    }
}
