import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import RotoCore

@MainActor
final class ClipboardPanelController: NSObject, ObservableObject {
    @Published var query = "" {
        didSet {
            if query != oldValue { refresh(keepSelection: false) }
        }
    }
    @Published private(set) var results: [ClipboardItem] = []
    @Published private(set) var selection = 0
    @Published private(set) var canPaste = true
    @Published private(set) var scrollToTop = 0

    let history: ClipboardHistory
    let monitor: ClipboardMonitor
    var popupScreen: PopupScreen = .primary
    private weak var searchField: NSTextField?

    private static let size = NSSize(width: 780, height: 500)

    private lazy var panel: FloatingPanel = {
        let panel = FloatingPanel(size: Self.size)
        let host = NSHostingView(rootView: ClipboardPanelView(model: self))
        host.frame = NSRect(origin: .zero, size: Self.size)
        panel.embed(rootView: host)
        panel.onKeyDown = { [weak self] event in
            self?.handleKey(event) ?? false
        }
        panel.onDismiss = { [weak self] in
            self?.query = ""
        }
        return panel
    }()

    init(history: ClipboardHistory, monitor: ClipboardMonitor) {
        self.history = history
        self.monitor = monitor
        super.init()
    }

    var isVisible: Bool { panel.isShown }

    var selectedItem: ClipboardItem? {
        results.indices.contains(selection) ? results[selection] : nil
    }

    /// Builds the window ahead of the first hotkey press so opening is instant.
    func prepare() {
        ClipboardFiles.removeStaleExports()
        refresh(keepSelection: false)
        panel.contentView?.layoutSubtreeIfNeeded()
    }

    func toggle() {
        if panel.isShown {
            panel.dismiss()
        } else {
            show()
        }
    }

    func show() {
        canPaste = PermissionCache.current.canPostEvents
        query = ""
        refresh(keepSelection: false)
        panel.focusView = searchField
        panel.present(screen: popupScreen)
        // Asking macOS costs a round trip to the permission daemon; do it after
        // the window is up, so a banner appears a frame late instead of the popup.
        PermissionCache.refresh { [weak self] permissions in
            self?.canPaste = permissions.canPostEvents
        }
        announceSelection()
    }

    func dismiss(animated: Bool = true) {
        panel.dismiss(animated: animated)
    }

    func attach(_ field: NSTextField) {
        searchField = field
        PanelFocus.focusWhenReady(field)
    }

    /// History changed underneath (new copy, deletion) while the panel is open.
    func historyDidChange() {
        guard panel.isShown else { return }
        refresh(keepSelection: true)
    }

    // MARK: - Actions

    func select(_ index: Int) {
        guard results.indices.contains(index), index != selection else { return }
        selection = index
        announceSelection()
    }

    func paste(at index: Int) {
        guard results.indices.contains(index) else { return }
        let item = results[index]
        // On the clipboard first, so the entry is usable even if the keystroke is blocked.
        monitor.write(item)
        panel.dismissForInsertion {
            Paster.pasteCommandV()
        }
    }

    func copySelected() {
        guard let item = selectedItem else { return }
        monitor.write(item)
        panel.dismiss()
    }

    func deleteSelected() {
        guard let item = selectedItem else { return }
        monitor.remove(item)
        Announcer.say("Deleted")
    }

    /// Space-bar style preview of a copied image or file, over the popup.
    func quickLookSelected() {
        // Already previewing: ⌘Y closes it again, whatever is selected by now —
        // otherwise landing on a text entry left no way to dismiss it but a beep.
        if panel.hideQuickLook() {
            panel.makeKey()
            return
        }
        guard let item = selectedItem else { return }
        let urls = ClipboardFiles.urls(for: item)
        guard !urls.isEmpty else {
            NSSound.beep()
            return
        }
        panel.showQuickLook(urls)
    }

    /// Opens a copied image or file in its default app (Preview for images and PDFs).
    func openSelected() {
        guard let item = selectedItem else { return }
        let urls = ClipboardFiles.urls(for: item)
        guard !urls.isEmpty else {
            NSSound.beep()
            return
        }
        panel.dismiss(animated: false)
        for url in urls {
            NSWorkspace.shared.open(url)
        }
    }

    private func refresh(keepSelection: Bool) {
        let previous = selectedItem?.id
        results = history.filtered(query)
        if keepSelection, let previous, let index = results.firstIndex(where: { $0.id == previous }) {
            selection = index
        } else {
            selection = keepSelection ? min(selection, max(results.count - 1, 0)) : 0
        }
        if !keepSelection {
            scrollToTop += 1
        }
    }

    private func move(by delta: Int) {
        guard !results.isEmpty else { return }
        select(min(max(selection + delta, 0), results.count - 1))
    }

    private func announceSelection() {
        guard let item = selectedItem else {
            Announcer.say(query.isEmpty ? "Clipboard history is empty" : "No matches")
            return
        }
        Announcer.say("\(ClipboardText.title(for: item)), \(selection + 1) of \(results.count)")
    }

    // MARK: - Keys

    func handleKey(_ event: NSEvent) -> Bool {
        let modifiers = PanelKey.modifiers(event)
        switch (event.keyCode, modifiers) {
        case (PanelKey.up, []):
            move(by: -1)
        case (PanelKey.down, []):
            move(by: 1)
        case (PanelKey.up, .command), (PanelKey.home, _):
            select(0)
        case (PanelKey.down, .command), (PanelKey.end, _):
            select(results.count - 1)
        case (PanelKey.pageUp, _):
            move(by: -8)
        case (PanelKey.pageDown, _):
            move(by: 8)
        case (PanelKey.returnKey, []), (PanelKey.keypadEnter, []):
            paste(at: selection)
        case (PanelKey.returnKey, .command), (PanelKey.keypadEnter, .command):
            copySelected()
        case (PanelKey.delete, .command), (PanelKey.forwardDelete, .command):
            deleteSelected()
        case (PanelKey.escape, []):
            if query.isEmpty {
                panel.dismiss()
            } else {
                query = ""
            }
        default:
            if modifiers == .command, let digit = PanelKey.digits[event.keyCode] {
                paste(at: digit - 1)
            } else if modifiers == .control, PanelKey.letter(event) == "n" {
                move(by: 1)
            } else if modifiers == .control, PanelKey.letter(event) == "p" {
                move(by: -1)
            } else if modifiers == .command, PanelKey.letter(event) == "y" {
                quickLookSelected()
            } else if modifiers == .command, PanelKey.letter(event) == "o" {
                openSelected()
            } else if modifiers == .command, PanelKey.letter(event) == "c", !searchFieldHasSelection {
                // Nothing selected in the search box: ⌘C copies the highlighted entry.
                copySelected()
            } else {
                return false
            }
        }
        return true
    }

    private var searchFieldHasSelection: Bool {
        guard let editor = searchField?.currentEditor() else { return false }
        return editor.selectedRange.length > 0
    }

    var hints: [KeyHint] {
        [
            KeyHint(keys: "↵", label: "Paste"),
            KeyHint(keys: "⌘↵", label: "Copy"),
            KeyHint(keys: "⌘1–9", label: "Quick paste"),
            KeyHint(keys: "⌘⌫", label: "Delete"),
        ]
    }

    var status: String {
        let total = history.all.count
        if query.isEmpty {
            return total == 1 ? "1 item" : "\(total) items"
        }
        return "\(results.count) of \(total)"
    }
}

// MARK: - Views

struct ClipboardPanelView: View {
    @ObservedObject var model: ClipboardPanelController

    var body: some View {
        PanelChrome(
            query: $model.query,
            placeholder: "Search clipboard history",
            status: model.status,
            hints: model.hints,
            needsAccessibility: !model.canPaste,
            onFieldCreated: model.attach
        ) {
            if model.results.isEmpty {
                if model.query.isEmpty {
                    EmptyState(
                        symbol: "clipboard",
                        title: "Nothing copied yet",
                        message: "Copy text, images, or files and they show up here."
                    )
                } else {
                    EmptyState(
                        symbol: "magnifyingglass",
                        title: "No matches",
                        message: "Nothing in your clipboard history matches “\(model.query)”."
                    )
                }
            } else {
                HStack(spacing: 12) {
                    list
                        .frame(width: 320)
                    Divider()
                    ClipboardPreview(item: model.selectedItem, model: model)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(model.results.enumerated()), id: \.element.id) { index, item in
                        ClipboardRow(
                            item: item,
                            isSelected: index == model.selection,
                            shortcut: index < 9 ? index + 1 : nil
                        )
                        .equatable()
                        .id(item.id)
                        .onTapGesture(count: 2) {
                            model.paste(at: index)
                        }
                        .simultaneousGesture(TapGesture().onEnded {
                            model.select(index)
                        })
                        .accessibilityAction {
                            model.paste(at: index)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .onChange(of: model.selection) { _, _ in
                if let id = model.selectedItem?.id {
                    proxy.scrollTo(id)
                }
            }
            .onChange(of: model.scrollToTop) { _, _ in
                if let id = model.results.first?.id {
                    proxy.scrollTo(id, anchor: .top)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Clipboard history")
    }
}

struct ClipboardRow: View, Equatable {
    let item: ClipboardItem
    let isSelected: Bool
    let shortcut: Int?
    @State private var hovering = false

    /// Moving the selection must not rebuild every visible row, only the two
    /// that changed; hover is this row's own state and drives itself.
    nonisolated static func == (lhs: ClipboardRow, rhs: ClipboardRow) -> Bool {
        lhs.item == rhs.item && lhs.isSelected == rhs.isSelected && lhs.shortcut == rhs.shortcut
    }

    var body: some View {
        HStack(spacing: 10) {
            ClipboardThumbnail(item: item)
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(ClipboardText.title(for: item))
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(ClipboardText.subtitle(for: item))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let shortcut {
                Text("⌘\(shortcut)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(SelectionBackground(isSelected: isSelected, isHovered: hovering))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(ClipboardText.title(for: item)), \(ClipboardText.subtitle(for: item))")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

private struct ClipboardThumbnail: View {
    let item: ClipboardItem

    var body: some View {
        switch item.kind {
        case .image:
            ClipboardImage(item: item, maxPixel: 96, contentMode: .fill) {
                symbol("photo")
            }
        case .files:
            if let url = item.fileURLs?.first {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                symbol("doc")
            }
        case .text:
            if let icon = AppIcons.icon(bundleID: item.bundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                symbol("text.alignleft")
            }
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
    }
}

private struct ClipboardPreview: View {
    let item: ClipboardItem?
    @ObservedObject var model: ClipboardPanelController

    var body: some View {
        if let item {
            VStack(alignment: .leading, spacing: 10) {
                content(for: item)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    // Start every entry scrolled to the top.
                    .id(item.id)
                Divider()
                details(for: item)
                if item.kind != .text {
                    HStack(spacing: 8) {
                        Button {
                            model.quickLookSelected()
                        } label: {
                            Label("Quick Look  ⌘Y", systemImage: "eye")
                        }
                        Button {
                            model.openSelected()
                        } label: {
                            Label("\(ClipboardFiles.openTitle(for: item))  ⌘O", systemImage: "arrow.up.forward.app")
                        }
                    }
                    .controlSize(.small)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Preview")
        }
    }

    @ViewBuilder
    private func content(for item: ClipboardItem) -> some View {
        switch item.kind {
        case .image:
            ClipboardImage(item: item, maxPixel: 1024, contentMode: .fit) {
                ProgressView()
                    .controlSize(.small)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("Image")
        case .files:
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(item.fileURLs ?? [], id: \.self) { url in
                        HStack(spacing: 8) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                .resizable()
                                .frame(width: 28, height: 28)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(url.lastPathComponent)
                                    .font(.system(size: 13, weight: .medium))
                                Text(url.deletingLastPathComponent().path)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .truncationMode(.middle)
                            }
                            .lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .text:
            ScrollView {
                Text(ClipboardText.preview(for: item))
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.trailing, 4)
            }
        }
    }

    private func details(for item: ClipboardItem) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            if let appName = item.appName {
                GridRow {
                    Text("Source")
                        .foregroundStyle(.secondary)
                    HStack(spacing: 5) {
                        if let icon = AppIcons.icon(bundleID: item.bundleID) {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 14, height: 14)
                                .accessibilityHidden(true)
                        }
                        Text(appName)
                            .lineLimit(1)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            detail("Copied", item.createdAt.formatted(date: .abbreviated, time: .shortened))
            switch item.kind {
            case .image:
                if let image = item.image {
                    detail("Size", "\(image.pixelWidth) × \(image.pixelHeight)")
                }
            case .files:
                detail("Files", "\(item.fileURLs?.count ?? 0)")
            case .text:
                detail("Content", ClipboardText.counts(for: item))
            }
        }
        .font(.system(size: 11))
    }

    private func detail(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .accessibilityElement(children: .combine)
    }
}

@MainActor
enum ClipboardText {
    static func title(for item: ClipboardItem) -> String {
        switch item.kind {
        case .files:
            let urls = item.fileURLs ?? []
            let first = urls.first?.lastPathComponent ?? "File"
            return urls.count > 1 ? "\(first) and \(urls.count - 1) more" : first
        case .image:
            if let image = item.image {
                return "Image \(image.pixelWidth) × \(image.pixelHeight)"
            }
            return "Image"
        case .text:
            // Only the head matters for a one-line title; never split megabytes per row.
            let head = (item.text ?? "").prefix(2_000)
            let line = head.split(whereSeparator: \.isNewline)
                .first { !$0.allSatisfy(\.isWhitespace) }
                .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            return String(line.prefix(200))
        }
    }

    static func subtitle(for item: ClipboardItem) -> String {
        var parts = [RelativeTime.string(item.createdAt)]
        if let appName = item.appName, !appName.isEmpty {
            parts.append(appName)
        }
        return parts.joined(separator: " · ")
    }

    /// Enough text to fill the pane; laying out megabytes would stall the UI.
    static func preview(for item: ClipboardItem) -> String {
        let text = item.text ?? ""
        let limit = 5_000
        guard text.utf8.count > limit else { return text }
        let head = text.prefix(limit)
        return head.endIndex < text.endIndex ? String(head) + "…" : text
    }

    static func counts(for item: ClipboardItem) -> String {
        let text = item.text ?? ""
        let characters = text.count
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count
        let charLabel = characters == 1 ? "1 character" : "\(characters.formatted()) characters"
        return lines > 1 ? "\(charLabel) · \(lines.formatted()) lines" : charLabel
    }
}

/// Shows a downsampled copy of an image entry, decoded off the main thread.
private struct ClipboardImage<Placeholder: View>: View {
    let item: ClipboardItem
    let maxPixel: Int
    let contentMode: ContentMode
    @ViewBuilder var placeholder: () -> Placeholder
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image, contentMode == .fill {
                // A filled image is larger than its box; clip it to the box, not to itself.
                Color.clear
                    .overlay {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                    .clipped()
            } else if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                placeholder()
            }
        }
        .task(id: "\(item.id)-\(maxPixel)") {
            image = ImageCache.cached(item, maxPixel: maxPixel)
            if image == nil {
                image = await ImageCache.load(item, maxPixel: maxPixel)
            }
        }
    }
}

/// Downsampled images keyed by entry, so scrolling never decodes a full screenshot.
@MainActor
enum ImageCache {
    /// Where entry image bytes live; set once at launch.
    static var store = ClipboardImageStore()

    private static let images: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.totalCostLimit = 24 * 1024 * 1024
        return cache
    }()

    static func cached(_ item: ClipboardItem, maxPixel: Int) -> NSImage? {
        images.object(forKey: key(item, maxPixel))
    }

    static func load(_ item: ClipboardItem, maxPixel: Int) async -> NSImage? {
        guard let stored = item.image else { return nil }
        let store = store
        let cgImage = await Task.detached(priority: .userInitiated) {
            thumbnail(stored, in: store, maxPixel: maxPixel)
        }.value
        guard let cgImage else { return nil }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        images.setObject(image, forKey: key(item, maxPixel), cost: cgImage.width * cgImage.height * 4)
        return image
    }

    private static func key(_ item: ClipboardItem, _ maxPixel: Int) -> NSString {
        "\(item.id.uuidString)-\(maxPixel)" as NSString
    }

    /// Decodes straight from the file when there is one, so the full PNG never sits in memory.
    nonisolated private static func thumbnail(_ image: StoredImage, in store: ClipboardImageStore, maxPixel: Int) -> CGImage? {
        let source: CGImageSource?
        if let url = store.fileURL(for: image) {
            source = CGImageSourceCreateWithURL(url as CFURL, nil)
        } else {
            source = store.data(for: image).flatMap { CGImageSourceCreateWithData($0 as CFData, nil) }
        }
        guard let source else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// Files on disk for entries Quick Look and other apps can open.
@MainActor
enum ClipboardFiles {
    /// Private per-user temp folder; images are exported here only when opened.
    private static var directory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("roto-clipboard", isDirectory: true)
    }

    static func urls(for item: ClipboardItem) -> [URL] {
        switch item.kind {
        case .files:
            return (item.fileURLs ?? []).filter { FileManager.default.fileExists(atPath: $0.path) }
        case .image:
            return exportedImage(for: item).map { [$0] } ?? []
        case .text:
            return []
        }
    }

    static func openTitle(for item: ClipboardItem) -> String {
        let appURL: URL?
        switch item.kind {
        case .files:
            appURL = item.fileURLs?.first.flatMap { NSWorkspace.shared.urlForApplication(toOpen: $0) }
        case .image:
            appURL = NSWorkspace.shared.urlForApplication(toOpen: .png)
        case .text:
            appURL = nil
        }
        guard let appURL else { return "Open" }
        return "Open in " + FileManager.default.displayName(atPath: appURL.path).replacingOccurrences(of: ".app", with: "")
    }

    /// Exports from earlier runs are no longer referenced by anything.
    static func removeStaleExports() {
        try? FileManager.default.removeItem(at: directory)
    }

    private static func exportedImage(for item: ClipboardItem) -> URL? {
        guard let image = item.image, let data = ImageCache.store.data(for: image) else { return nil }
        let url = directory.appendingPathComponent("\(item.id.uuidString).png")
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return url
        } catch {
            return nil
        }
    }
}
