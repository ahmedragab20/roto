import AppKit
@preconcurrency import ScreenCaptureKit

/// Window thumbnails for the switcher. Opt-in: needs Screen Recording, and roto
/// never triggers that prompt unless the user asks for previews.
@MainActor
final class WindowPreviews {
    private var cache: [CGWindowID: NSImage] = [:]
    private var content: SCShareableContent?

    /// Last known answer; asking macOS directly blocks for about 6 ms.
    var isAllowed: Bool {
        PermissionCache.current.canCaptureScreen
    }

    func requestAccess() {
        if !CGRequestScreenCaptureAccess(),
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        PermissionCache.refresh()
    }

    /// Windows change between showings; start fresh each time the switcher opens.
    func reset() {
        cache.removeAll()
        content = nil
    }

    func cached(_ windowID: CGWindowID) -> NSImage? {
        cache[windowID]
    }

    func image(for windowID: CGWindowID) async -> NSImage? {
        if let cached = cache[windowID] {
            return cached
        }
        guard isAllowed else { return nil }
        do {
            if content == nil {
                content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            }
            guard let window = content?.windows.first(where: { $0.windowID == windowID }) else { return nil }
            let longest = max(window.frame.width, window.frame.height, 1)
            let scale = min(1, 900 / longest) * 2
            let configuration = SCStreamConfiguration()
            configuration.width = max(Int(window.frame.width * scale), 1)
            configuration.height = max(Int(window.frame.height * scale), 1)
            configuration.showsCursor = false
            let cgImage = try await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(desktopIndependentWindow: window),
                configuration: configuration
            )
            let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            cache[windowID] = image
            return image
        } catch {
            return nil
        }
    }
}
