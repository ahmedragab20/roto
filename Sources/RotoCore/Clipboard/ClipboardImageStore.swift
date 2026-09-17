import CryptoKit
import Foundation
import ImageIO

/// A copied image as history sees it: a content digest plus what the UI shows.
/// The bytes live in a `ClipboardImageStore`, not in the history.
public struct StoredImage: Equatable, Codable, Sendable {
    public var digest: String
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var byteCount: Int

    public init(digest: String, pixelWidth: Int, pixelHeight: Int, byteCount: Int) {
        self.digest = digest
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.byteCount = byteCount
    }
}

/// Image bytes for clipboard entries, content-addressed so repeats cost nothing.
/// With a directory, each image is a `<digest>.png` file (0600) and costs no memory
/// until it is read; without one, images stay in memory and never touch disk.
public final class ClipboardImageStore: @unchecked Sendable {
    private let lock = NSLock()
    private var directory: URL?
    private var memory: [String: Data] = [:]

    public init(directory: URL? = nil) {
        self.directory = directory
    }

    public var isOnDisk: Bool {
        lock.lock()
        defer { lock.unlock() }
        return directory != nil
    }

    /// Stores PNG bytes. Returns nil when the bytes are not a readable image.
    public func put(_ png: Data) -> StoredImage? {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        let digest = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
        let image = StoredImage(digest: digest, pixelWidth: width, pixelHeight: height, byteCount: png.count)

        lock.lock()
        defer { lock.unlock() }
        if let directory {
            let url = Self.file(digest, in: directory)
            guard FileManager.default.fileExists(atPath: url.path) || Self.write(png, to: url, in: directory) else {
                return nil
            }
        } else {
            memory[digest] = png
        }
        return image
    }

    public func contains(_ image: StoredImage) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let directory {
            return FileManager.default.fileExists(atPath: Self.file(image.digest, in: directory).path)
        }
        return memory[image.digest] != nil
    }

    /// The bytes, memory-mapped when on disk so reading a big image stays cheap.
    public func data(for image: StoredImage) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        if let directory {
            return try? Data(contentsOf: Self.file(image.digest, in: directory), options: .alwaysMapped)
        }
        return memory[image.digest]
    }

    /// The file, when images are on disk. Treat it as read-only.
    public func fileURL(for image: StoredImage) -> URL? {
        lock.lock()
        defer { lock.unlock() }
        guard let directory else { return nil }
        let url = Self.file(image.digest, in: directory)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Switches between disk and memory, carrying over the images still in use.
    public func relocate(to newDirectory: URL?, keeping digests: Set<String>) {
        lock.lock()
        defer { lock.unlock() }
        guard newDirectory != directory else { return }
        switch (directory, newDirectory) {
        case (nil, let target?):
            for (digest, data) in memory where digests.contains(digest) {
                _ = Self.write(data, to: Self.file(digest, in: target), in: target)
            }
            memory.removeAll()
        case (let current?, nil):
            for digest in digests {
                if let data = try? Data(contentsOf: Self.file(digest, in: current)) {
                    memory[digest] = data
                }
            }
            try? FileManager.default.removeItem(at: current)
        case (let current?, let target?):
            for digest in digests {
                let url = Self.file(digest, in: current)
                if let data = try? Data(contentsOf: url, options: .alwaysMapped) {
                    _ = Self.write(data, to: Self.file(digest, in: target), in: target)
                }
            }
            try? FileManager.default.removeItem(at: current)
        case (nil, nil):
            break
        }
        directory = newDirectory
    }

    /// Drops every image no entry refers to any more.
    public func prune(keeping digests: Set<String>) {
        lock.lock()
        defer { lock.unlock() }
        guard let directory else {
            memory = memory.filter { digests.contains($0.key) }
            return
        }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names where name.hasSuffix(".png") && !digests.contains(String(name.dropLast(4))) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    private static func file(_ digest: String, in directory: URL) -> URL {
        directory.appendingPathComponent("\(digest).png")
    }

    private static func write(_ data: Data, to url: URL, in directory: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return true
        } catch {
            return false
        }
    }
}
