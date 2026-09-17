import Foundation

public struct ClipboardItem: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var text: String?
    public var image: StoredImage?
    public var fileURLs: [URL]?
    public var createdAt: Date
    public var appName: String?
    public var bundleID: String?

    public init(
        id: UUID = UUID(),
        text: String? = nil,
        image: StoredImage? = nil,
        fileURLs: [URL]? = nil,
        createdAt: Date = Date(),
        appName: String? = nil,
        bundleID: String? = nil
    ) {
        self.id = id
        self.text = text
        self.image = image
        self.fileURLs = fileURLs
        self.createdAt = createdAt
        self.appName = appName
        self.bundleID = bundleID
    }

    public enum Kind: Sendable {
        case text
        case image
        case files
    }

    public var kind: Kind {
        if let fileURLs, !fileURLs.isEmpty { return .files }
        if image != nil { return .image }
        return .text
    }

    public var isEmpty: Bool {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty && image == nil && (fileURLs ?? []).isEmpty
    }

    public func hasSameContent(as other: ClipboardItem) -> Bool {
        text == other.text && fileURLs == other.fileURLs && image?.digest == other.image?.digest
    }
}

public final class ClipboardHistory: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [ClipboardItem]
    private var searchFields: [UUID: [SearchField]] = [:]
    public private(set) var capacity: Int
    /// Seconds an entry stays after it was last copied; nil keeps entries forever.
    public private(set) var maxAge: TimeInterval?

    public init(capacity: Int = 200, items: [ClipboardItem] = []) {
        self.capacity = max(1, capacity)
        self.items = Array(items.prefix(self.capacity))
        for item in self.items {
            searchFields[item.id] = Self.fields(for: item)
        }
    }

    /// Newest first.
    public var all: [ClipboardItem] {
        lock.lock()
        defer { lock.unlock() }
        return items
    }

    public func setCapacity(_ capacity: Int) {
        lock.lock()
        defer { lock.unlock() }
        self.capacity = max(1, capacity)
        trimLocked()
    }

    public func setMaxAge(_ maxAge: TimeInterval?) {
        lock.lock()
        self.maxAge = maxAge
        lock.unlock()
        removeExpired()
    }

    /// Drops entries last copied before the age limit. Returns true if any went.
    @discardableResult
    public func removeExpired(now: Date = Date()) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let before = items.count
        items.removeAll { item in
            guard isExpiredLocked(item, now: now) else { return false }
            searchFields[item.id] = nil
            return true
        }
        return items.count != before
    }

    /// Adds a fresh copy. Copying the same content again moves it to the top.
    public func add(_ item: ClipboardItem) {
        guard !item.isEmpty else { return }
        // Folding a large copy is the slow part; keep it outside the lock.
        let content = Self.contentFields(for: item)
        lock.lock()
        defer { lock.unlock() }

        var entry = item
        if let index = items.firstIndex(where: { $0.hasSameContent(as: item) }) {
            let existing = items.remove(at: index)
            searchFields[existing.id] = nil
            entry.id = existing.id
            entry.appName = item.appName ?? existing.appName
            entry.bundleID = item.bundleID ?? existing.bundleID
        }
        items.insert(entry, at: 0)
        searchFields[entry.id] = content + Self.appFields(for: entry)
        trimLocked()
    }

    /// Adds older entries (e.g. loaded from disk) below the current ones.
    public func appendOlder(_ older: [ClipboardItem]) {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        for item in older where !item.isEmpty && !isExpiredLocked(item, now: now)
            && !items.contains(where: { $0.hasSameContent(as: item) }) {
            guard items.count < capacity else { break }
            items.append(item)
            searchFields[item.id] = Self.fields(for: item)
        }
    }

    /// Moves an entry to the top, as if it was just copied. Returns false if it is gone.
    @discardableResult
    public func promote(_ id: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let index = items.firstIndex(where: { $0.id == id }) else { return false }
        var item = items.remove(at: index)
        item.createdAt = Date()
        items.insert(item, at: 0)
        return true
    }

    public func remove(_ id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        items.removeAll { $0.id == id }
        searchFields[id] = nil
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        items.removeAll()
        searchFields.removeAll()
    }

    /// Matching entries. Strong matches (whole words, prefixes) come before
    /// loose ones; inside each band the newest entry wins.
    public func filtered(_ query: String) -> [ClipboardItem] {
        let prepared = SearchQuery(query)
        lock.lock()
        let snapshot = items
        let fields = searchFields
        lock.unlock()
        if prepared.isEmpty { return snapshot }

        return snapshot.enumerated()
            .compactMap { offset, item -> (band: Int, offset: Int, item: ClipboardItem)? in
                let itemFields = fields[item.id] ?? Self.fields(for: item)
                guard let score = Fuzzy.score(prepared, fields: itemFields) else { return nil }
                let band = score >= 75 ? 2 : (score >= 45 ? 1 : 0)
                return (band, offset, item)
            }
            .sorted { $0.band != $1.band ? $0.band > $1.band : $0.offset < $1.offset }
            .map(\.item)
    }

    public func encode() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(all)
    }

    /// Digests of every image an entry still refers to.
    public var imageDigests: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return Set(items.compactMap { $0.image?.digest })
    }

    /// Reads saved history. Images whose bytes are gone are dropped; images saved
    /// inline by older versions move into `store`.
    public static func decode(from data: Data, capacity: Int, store: ClipboardImageStore) throws -> ClipboardHistory {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let saved = try decoder.decode([SavedItem].self, from: data)
        let items = saved.compactMap { saved -> ClipboardItem? in
            var item = saved.item
            if let legacy = saved.imagePNG, item.image == nil {
                item.image = store.put(legacy)
            }
            if let image = item.image, !store.contains(image) {
                item.image = nil
            }
            return item.isEmpty ? nil : item
        }
        return ClipboardHistory(capacity: capacity, items: items)
    }

    private struct SavedItem: Decodable {
        var item: ClipboardItem
        var imagePNG: Data?

        private enum CodingKeys: String, CodingKey {
            case imagePNG
        }

        init(from decoder: Decoder) throws {
            item = try ClipboardItem(from: decoder)
            imagePNG = try decoder.container(keyedBy: CodingKeys.self).decodeIfPresent(Data.self, forKey: .imagePNG)
        }
    }

    private func isExpiredLocked(_ item: ClipboardItem, now: Date) -> Bool {
        guard let maxAge else { return false }
        return now.timeIntervalSince(item.createdAt) > maxAge
    }

    private func trimLocked() {
        guard items.count > capacity else { return }
        for item in items[capacity...] {
            searchFields[item.id] = nil
        }
        items.removeLast(items.count - capacity)
    }

    private static func fields(for item: ClipboardItem) -> [SearchField] {
        contentFields(for: item) + appFields(for: item)
    }

    private static func appFields(for item: ClipboardItem) -> [SearchField] {
        guard let appName = item.appName, !appName.isEmpty else { return [] }
        return [SearchField(appName, weight: 0.6, minimumTokenLength: 2, isPrimary: false)]
    }

    private static func contentFields(for item: ClipboardItem) -> [SearchField] {
        var fields: [SearchField] = []
        if let text = item.text, !text.isEmpty {
            fields.append(SearchField(text))
        }
        if item.image != nil {
            fields.append(SearchField("image picture screenshot", weight: 0.7, fuzzy: false, minimumTokenLength: 3, isPrimary: false))
        }
        for url in item.fileURLs ?? [] {
            fields.append(SearchField(url.lastPathComponent))
            fields.append(SearchField(
                url.deletingLastPathComponent().path,
                weight: 0.5,
                fuzzy: false,
                minimumTokenLength: 2,
                isPrimary: false
            ))
        }
        if let urls = item.fileURLs, !urls.isEmpty {
            fields.append(SearchField(
                urls.count == 1 ? "file" : "files",
                weight: 0.7,
                fuzzy: false,
                minimumTokenLength: 3,
                isPrimary: false
            ))
        }
        return fields
    }
}
