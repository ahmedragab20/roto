import Foundation
import Testing
@testable import RotoCore

struct ClipboardHistoryTests {
    @Test func dropsEmpty() {
        let history = ClipboardHistory(capacity: 5)
        history.add(ClipboardItem(text: "  "))
        history.add(ClipboardItem())
        #expect(history.all.isEmpty)
    }

    @Test func newestFirstAndCapacity() {
        let history = ClipboardHistory(capacity: 2)
        history.add(ClipboardItem(text: "a"))
        history.add(ClipboardItem(text: "b"))
        history.add(ClipboardItem(text: "c"))
        #expect(history.all.map(\.text) == ["c", "b"])
    }

    @Test func dedupesTextAndMovesToFront() {
        let history = ClipboardHistory(capacity: 10)
        history.add(ClipboardItem(text: "a"))
        history.add(ClipboardItem(text: "b"))
        history.add(ClipboardItem(text: "a"))
        #expect(history.all.map(\.text) == ["a", "b"])
        #expect(history.all.count == 2)
    }

    @Test func filterIsCaseInsensitive() {
        let history = ClipboardHistory()
        history.add(ClipboardItem(text: "Hello World", appName: "Safari"))
        history.add(ClipboardItem(text: "other"))
        history.add(ClipboardItem(image: StoredImage(digest: "abc", pixelWidth: 1, pixelHeight: 1, byteCount: 3), appName: "Preview"))
        #expect(history.filtered("hello").count == 1)
        #expect(history.filtered("IMAGE").count == 1)
        #expect(history.filtered("safar").first?.appName == "Safari")
        #expect(history.filtered("").count == 3)
    }

    @Test func roundTripsJSON() throws {
        let history = ClipboardHistory(capacity: 8)
        history.add(ClipboardItem(text: "secret"))
        let data = try history.encode()
        let loaded = try ClipboardHistory.decode(from: data, capacity: 8, store: ClipboardImageStore())
        #expect(loaded.all.first?.text == "secret")
    }

    @Test func dropsEntriesPastMaxAge() {
        let now = Date()
        let history = ClipboardHistory(capacity: 10, items: [
            ClipboardItem(text: "fresh", createdAt: now.addingTimeInterval(-3_600)),
            ClipboardItem(text: "stale", createdAt: now.addingTimeInterval(-3 * 86_400)),
        ])
        #expect(history.removeExpired(now: now) == false)

        history.setMaxAge(2 * 86_400)
        #expect(history.all.map(\.text) == ["fresh"])

        history.appendOlder([ClipboardItem(text: "old", createdAt: now.addingTimeInterval(-5 * 86_400))])
        #expect(history.all.count == 1)
    }

    @Test func dedupesFilesAndKeepsID() {
        let url = URL(fileURLWithPath: "/tmp/a.txt")
        let first = ClipboardItem(fileURLs: [url])
        let history = ClipboardHistory(capacity: 10)
        history.add(first)
        history.add(ClipboardItem(text: "x"))
        history.add(ClipboardItem(fileURLs: [url]))
        #expect(history.all.count == 2)
        #expect(history.all.first?.id == first.id)
    }

    @Test func promoteMovesToTop() {
        let history = ClipboardHistory(capacity: 10)
        let a = ClipboardItem(text: "a")
        history.add(a)
        history.add(ClipboardItem(text: "b"))
        #expect(history.promote(a.id) == true)
        #expect(history.all.map(\.text) == ["a", "b"])
        #expect(history.promote(UUID()) == false)
    }

    @Test func removeDropsEntry() {
        let history = ClipboardHistory(capacity: 10)
        let hello = ClipboardItem(text: "hello")
        history.add(hello)
        history.add(ClipboardItem(text: "world"))
        history.remove(hello.id)
        #expect(history.filtered("hello").isEmpty)
        #expect(history.all.count == 1)
    }

    @Test func appendOlderGoesBelowAndSkipsDuplicates() {
        let history = ClipboardHistory(capacity: 3)
        history.add(ClipboardItem(text: "new"))
        history.appendOlder([
            ClipboardItem(text: "new"),
            ClipboardItem(text: "old1"),
            ClipboardItem(text: "old2"),
            ClipboardItem(text: "old3"),
        ])
        #expect(history.all.map(\.text) == ["new", "old1", "old2"])
    }

    @Test func filterPrefersStrongMatchesThenRecency() {
        let history = ClipboardHistory(capacity: 10)
        history.add(ClipboardItem(text: "configuration file"))
        history.add(ClipboardItem(text: "reconfig tool"))
        history.add(ClipboardItem(text: "my config"))
        #expect(history.filtered("config").map(\.text) == ["my config", "configuration file", "reconfig tool"])
    }

    @Test func filesAreSearchableByName() {
        let history = ClipboardHistory(capacity: 10)
        history.add(ClipboardItem(fileURLs: [URL(fileURLWithPath: "/Users/me/Documents/report.pdf")]))
        history.add(ClipboardItem(text: "other"))
        #expect(history.filtered("report").count == 1)
        #expect(history.filtered("file").count == 1)
    }

    @Test func decodesLegacyJSONWithoutFileURLs() throws {
        let json = #"[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","text":"legacy","createdAt":"2026-01-01T00:00:00Z"}]"#
        let loaded = try ClipboardHistory.decode(from: Data(json.utf8), capacity: 5, store: ClipboardImageStore())
        #expect(loaded.all.first?.text == "legacy")
        #expect(loaded.all.first?.fileURLs == nil)
    }

    @Test func kindReflectsContent() {
        #expect(ClipboardItem(text: "a").kind == .text)
        #expect(ClipboardItem(image: StoredImage(digest: "a", pixelWidth: 1, pixelHeight: 1, byteCount: 1)).kind == .image)
        #expect(ClipboardItem(fileURLs: [URL(fileURLWithPath: "/tmp/a")]).kind == .files)
    }
}

struct EmojiCatalogTests {
    @Test func filtersByNameKeywordAndGroup() {
        let catalog = EmojiCatalog(entries: [
            EmojiEntry(emoji: "😀", name: "grinning face", group: "Smileys & Emotion", keywords: ["smile", "happy"]),
            EmojiEntry(emoji: "🔥", name: "fire", group: "Travel & Places", keywords: ["hot"]),
        ])
        #expect(catalog.filtered("grin").map(\.emoji) == ["😀"])
        #expect(catalog.filtered("HOT").map(\.emoji) == ["🔥"])
        #expect(catalog.filtered("travel").map(\.emoji) == ["🔥"])
        #expect(catalog.filtered("").count == 2)
    }

    @Test func cryDoesNotReturnGrinning() {
        let catalog = EmojiCatalog(entries: [
            EmojiEntry(
                emoji: "😀",
                name: "grinning face",
                group: "Smileys & Emotion",
                keywords: ["smile", "happy", "eyes"]
            ),
            EmojiEntry(
                emoji: "😢",
                name: "crying face",
                group: "Smileys & Emotion",
                keywords: ["cry", "sad", "tear"]
            ),
        ])
        #expect(catalog.filtered("cry").map(\.emoji) == ["😢"])
    }

    @Test func dropsExcludedEntries() {
        let catalog = EmojiCatalog(entries: [
            EmojiEntry(emoji: "🇮🇱", name: "flag: Israel", group: "Flags"),
            EmojiEntry(emoji: "😀", name: "grinning face", group: "Smileys & Emotion"),
        ])
        #expect(catalog.entries.map(\.emoji) == ["😀"])
    }

    @Test func appliesSkinToneAndRecents() {
        let catalog = EmojiCatalog(entries: EmojiCatalog.fallback, skinTone: "dark")
        let wave = catalog.entries.first { $0.emoji == "👋" }!
        #expect(wave.glyph(skinTone: "dark") == "👋🏿")
        #expect(wave.glyph(skinTone: "default") == "👋")
        catalog.recordUse("👋")
        catalog.recordUse("🔥")
        catalog.recordUse("👋")
        #expect(catalog.recents == ["👋", "🔥"])
        #expect(catalog.recentEntries().first?.emoji == "👋")
    }

    @Test func searchPrefersCommonEmoji() {
        let catalog = EmojiCatalog(entries: [
            EmojiEntry(emoji: "♥️", name: "heart suit", group: "Activities", keywords: ["card", "game", "heart"]),
            EmojiEntry(emoji: "❤️", name: "red heart", group: "Smileys & Emotion", keywords: ["heart", "love"]),
        ])
        #expect(catalog.filtered("heart").first?.emoji == "❤️")
        #expect(catalog.filtered("heart red").first?.emoji == "❤️")
        #expect(catalog.filtered("love").map(\.emoji) == ["❤️"])
    }

    @Test func recentsBoostRanking() {
        let catalog = EmojiCatalog(entries: [
            EmojiEntry(emoji: "🪐", name: "ringed planet", group: "Travel & Places", keywords: ["planet"]),
            EmojiEntry(emoji: "🌍", name: "globe showing Europe-Africa", group: "Travel & Places", keywords: ["planet", "earth"]),
        ])
        #expect(catalog.filtered("planet").first?.emoji == "🪐")
        catalog.recordUse("🌍")
        #expect(catalog.filtered("planet").first?.emoji == "🌍")
    }

    @Test func browseSectionsPutRecentsFirst() {
        let catalog = EmojiCatalog(entries: EmojiCatalog.fallback, recents: ["🔥"])
        let sections = catalog.browseSections()
        #expect(sections.map(\.title) == [
            "Recently Used", "Smileys & Emotion", "People & Body", "Travel & Places", "Symbols", "Activities",
        ])
        #expect(sections.first?.entries.map(\.emoji) == ["🔥"])
        #expect(EmojiCatalog(entries: EmojiCatalog.fallback).browseSections().first?.title == "Smileys & Emotion")
    }
}
