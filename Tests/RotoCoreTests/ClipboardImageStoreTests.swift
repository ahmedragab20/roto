import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import RotoCore

struct ClipboardImageStoreTests {
    @Test func storesOnDiskByDigestAndDedupes() throws {
        let dir = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ClipboardImageStore(directory: dir)
        let png = makePNG(width: 3, height: 2)

        let first = try #require(store.put(png))
        let second = try #require(store.put(png))
        #expect(first == second)
        #expect(first.pixelWidth == 3 && first.pixelHeight == 2)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).count == 1)
        #expect(store.data(for: first) == png)
        let mode = try FileManager.default.attributesOfItem(atPath: store.fileURL(for: first)!.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
    }

    @Test func rejectsNonImages() {
        #expect(ClipboardImageStore().put(Data([1, 2, 3])) == nil)
    }

    @Test func prunesUnreferencedImages() throws {
        let dir = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ClipboardImageStore(directory: dir)
        let kept = try #require(store.put(makePNG(width: 1, height: 1)))
        let dropped = try #require(store.put(makePNG(width: 2, height: 2)))

        store.prune(keeping: [kept.digest])
        #expect(store.contains(kept))
        #expect(!store.contains(dropped))
    }

    @Test func relocatesBetweenMemoryAndDisk() throws {
        let dir = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ClipboardImageStore()
        let image = try #require(store.put(makePNG(width: 4, height: 4)))

        store.relocate(to: dir, keeping: [image.digest])
        #expect(store.fileURL(for: image) != nil)

        store.relocate(to: nil, keeping: [image.digest])
        #expect(store.fileURL(for: image) == nil)
        #expect(store.contains(image))
        #expect(!FileManager.default.fileExists(atPath: dir.path))
    }

    @Test func historySavesDigestsNotBytes() throws {
        let dir = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ClipboardImageStore(directory: dir)
        let png = makePNG(width: 64, height: 64)
        let history = ClipboardHistory(capacity: 4)
        history.add(ClipboardItem(image: store.put(png)))

        let data = try history.encode()
        #expect(data.count < png.count)
        let loaded = try ClipboardHistory.decode(from: data, capacity: 4, store: store)
        #expect(loaded.all.first?.image == history.all.first?.image)
    }

    @Test func migratesInlineImagesAndDropsMissingOnes() throws {
        let dir = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ClipboardImageStore(directory: dir)
        let png = makePNG(width: 5, height: 5)
        let legacy = """
        [
          {"id": "\(UUID())", "imagePNG": "\(png.base64EncodedString())", "createdAt": "2026-01-01T00:00:00Z"},
          {"id": "\(UUID())", "image": {"digest": "gone", "pixelWidth": 1, "pixelHeight": 1, "byteCount": 1}, "createdAt": "2026-01-01T00:00:00Z"},
          {"id": "\(UUID())", "text": "kept", "createdAt": "2026-01-01T00:00:00Z"}
        ]
        """

        let loaded = try ClipboardHistory.decode(from: Data(legacy.utf8), capacity: 10, store: store)
        #expect(loaded.all.count == 2)
        let image = try #require(loaded.all.first?.image)
        #expect(store.data(for: image) == png)
        #expect(loaded.all.last?.text == "kept")
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("roto-tests-\(UUID().uuidString)", isDirectory: true)
    }

    private func makePNG(width: Int, height: Int) -> Data {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }
}
