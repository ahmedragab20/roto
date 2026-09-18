import AppKit
import SwiftUI
import RotoCore

struct EmojiGridRow: Identifiable, Equatable {
    enum Kind: Equatable {
        case header(String)
        case cells(Range<Int>)
    }

    let kind: Kind

    var id: String {
        switch kind {
        case .header(let title): return "header:\(title)"
        case .cells(let range): return "cells:\(range.lowerBound)"
        }
    }
}

struct EmojiScrollTarget: Equatable {
    let rowID: String
    let anchor: UnitPoint?
    let token: Int
}

@MainActor
final class EmojiPanelController: NSObject, ObservableObject {
    @Published var query = "" {
        didSet {
            if query != oldValue { refresh() }
        }
    }
    @Published private(set) var rows: [EmojiGridRow] = []
    @Published private(set) var selection = 0
    @Published private(set) var hovered: Int?
    @Published private(set) var canPaste = true
    @Published private(set) var scrollTarget: EmojiScrollTarget?

    let catalog: EmojiCatalog
    var popupScreen: PopupScreen = .primary
    private(set) var entries: [EmojiEntry] = []
    private var sections: [(title: String?, range: Range<Int>)] = []
    private var cellRows: [Range<Int>] = []
    private var columns = EmojiPanelController.defaultColumns
    private var scrollToken = 0
    private weak var searchField: NSTextField?
    private let recentsQueue = DispatchQueue(label: "roto.emoji.recents", qos: .utility)

    static let cell: CGFloat = 48
    static let spacing: CGFloat = 4
    /// Room for a legacy (always visible) scroll bar so the last column never hides under it.
    static let scrollerAllowance: CGFloat = 16
    private static let size = NSSize(width: 680, height: 520)
    private static let defaultColumns = GridNavigation.columnCount(
        width: size.width - 32 - scrollerAllowance,
        cell: cell,
        spacing: spacing
    )

    private lazy var panel: FloatingPanel = {
        let panel = FloatingPanel(size: Self.size)
        let host = NSHostingView(rootView: EmojiPanelView(model: self))
        host.frame = NSRect(origin: .zero, size: Self.size)
        panel.embed(rootView: host)
        panel.onKeyDown = { [weak self] event in
            self?.handleKey(event) ?? false
        }
        panel.onDismiss = { [weak self] in
            self?.query = ""
            self?.hovered = nil
        }
        return panel
    }()

    init(catalog: EmojiCatalog) {
        self.catalog = catalog
        super.init()
    }

    var isVisible: Bool { panel.isShown }

    var isBrowsing: Bool {
        SearchQuery(query).isEmpty
    }

    func prepare() {
        refresh()
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
        // Recents may have changed since the last showing.
        refresh()
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

    func updateColumns(width: CGFloat) {
        let count = GridNavigation.columnCount(
            width: Double(width - Self.scrollerAllowance),
            cell: Double(Self.cell),
            spacing: Double(Self.spacing)
        )
        guard count != columns else { return }
        columns = count
        rebuildRows()
    }

    func glyph(at index: Int) -> String {
        entries[index].glyph(skinTone: catalog.skinTone)
    }

    func hover(_ index: Int, _ inside: Bool) {
        if inside {
            hovered = index
        } else if hovered == index {
            hovered = nil
        }
    }

    // MARK: - Actions

    func insert(at index: Int) {
        guard entries.indices.contains(index) else { return }
        let entry = entries[index]
        let glyph = entry.glyph(skinTone: catalog.skinTone)
        recordUse(entry)
        if !canPaste {
            // Typing is likely blocked; leave it on the clipboard as a fallback.
            copyToClipboard(glyph)
        }
        panel.dismissForInsertion {
            Paster.typeUnicode(glyph)
        }
    }

    func copySelected() {
        guard entries.indices.contains(selection) else { return }
        let entry = entries[selection]
        recordUse(entry)
        copyToClipboard(entry.glyph(skinTone: catalog.skinTone))
        panel.dismiss()
    }

    private func copyToClipboard(_ glyph: String) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(glyph, forType: .string)
    }

    private func recordUse(_ entry: EmojiEntry) {
        catalog.recordUse(entry.emoji)
        guard let data = try? catalog.encodeRecents() else { return }
        recentsQueue.async {
            try? FileManager.default.createDirectory(at: Paths.supportDirectory, withIntermediateDirectories: true)
            try? data.write(to: Paths.emojiRecentsFile, options: .atomic)
        }
    }

    // MARK: - Layout

    private func refresh() {
        var built: [(title: String?, entries: [EmojiEntry])] = []
        if isBrowsing {
            built = catalog.browseSections().map { ($0.title, $0.entries) }
        } else {
            let matches = catalog.filtered(query)
            if !matches.isEmpty {
                built = [(nil, matches)]
            }
        }

        entries = built.flatMap(\.entries)
        var offset = 0
        sections = built.map { section in
            defer { offset += section.entries.count }
            return (section.title, offset..<(offset + section.entries.count))
        }
        selection = 0
        hovered = nil
        rebuildRows()
        if let first = rows.first {
            scroll(to: first.id, anchor: .top)
        }
    }

    private func rebuildRows() {
        cellRows = GridNavigation.rows(sectionSizes: sections.map(\.range.count), columns: columns)
        var built: [EmojiGridRow] = []
        var next = 0
        for section in sections where !section.range.isEmpty {
            if let title = section.title {
                built.append(EmojiGridRow(kind: .header(title)))
            }
            while next < cellRows.count, cellRows[next].lowerBound < section.range.upperBound {
                built.append(EmojiGridRow(kind: .cells(cellRows[next])))
                next += 1
            }
        }
        rows = built
    }

    private func select(_ index: Int, revealHeader: Bool = false, anchor: UnitPoint? = nil) {
        guard entries.indices.contains(index) else { return }
        let changed = index != selection
        selection = index
        if let rowID = rowID(containing: index, preferHeader: revealHeader) {
            scroll(to: rowID, anchor: anchor)
        }
        if changed {
            announceSelection()
        }
    }

    private func move(dx: Int, dy: Int) {
        guard !entries.isEmpty else { return }
        let next = GridNavigation.move(index: selection, rows: cellRows, dx: dx, dy: dy)
        select(next, revealHeader: dy < 0 || dx < 0)
    }

    private func jumpSection(forward: Bool) {
        guard let current = sections.firstIndex(where: { $0.range.contains(selection) }) else { return }
        let target: Int
        if forward {
            target = current + 1
        } else {
            target = selection == sections[current].range.lowerBound ? current - 1 : current
        }
        guard sections.indices.contains(target) else { return }
        select(sections[target].range.lowerBound, revealHeader: true, anchor: .top)
    }

    /// Row to scroll to: the cell row, or its section header when moving up into
    /// a section's first row so the header does not stay hidden above.
    private func rowID(containing index: Int, preferHeader: Bool) -> String? {
        guard let position = rows.firstIndex(where: {
            if case .cells(let range) = $0.kind { return range.contains(index) }
            return false
        }) else { return nil }
        if preferHeader, position > 0, case .header = rows[position - 1].kind {
            return rows[position - 1].id
        }
        return rows[position].id
    }

    private func scroll(to rowID: String, anchor: UnitPoint?) {
        scrollToken += 1
        scrollTarget = EmojiScrollTarget(rowID: rowID, anchor: anchor, token: scrollToken)
    }

    private func announceSelection() {
        guard entries.indices.contains(selection) else {
            Announcer.say("No emoji found")
            return
        }
        Announcer.say(entries[selection].name)
    }

    // MARK: - Keys

    func handleKey(_ event: NSEvent) -> Bool {
        let modifiers = PanelKey.modifiers(event)
        switch (event.keyCode, modifiers) {
        case (PanelKey.up, []):
            move(dx: 0, dy: -1)
        case (PanelKey.down, []):
            move(dx: 0, dy: 1)
        case (PanelKey.left, []):
            move(dx: -1, dy: 0)
        case (PanelKey.right, []):
            move(dx: 1, dy: 0)
        case (PanelKey.up, .command), (PanelKey.home, _):
            select(0, revealHeader: true, anchor: .top)
        case (PanelKey.down, .command), (PanelKey.end, _):
            select(entries.count - 1)
        case (PanelKey.pageUp, _):
            move(dx: 0, dy: -6)
        case (PanelKey.pageDown, _):
            move(dx: 0, dy: 6)
        case (PanelKey.tab, []) where isBrowsing:
            jumpSection(forward: true)
        case (PanelKey.tab, .shift) where isBrowsing:
            jumpSection(forward: false)
        case (PanelKey.returnKey, []), (PanelKey.keypadEnter, []):
            insert(at: selection)
        case (PanelKey.returnKey, .command), (PanelKey.keypadEnter, .command):
            copySelected()
        case (PanelKey.escape, []):
            if query.isEmpty {
                panel.dismiss()
            } else {
                query = ""
            }
        default:
            if modifiers == .control, PanelKey.letter(event) == "n" {
                move(dx: 0, dy: 1)
            } else if modifiers == .control, PanelKey.letter(event) == "p" {
                move(dx: 0, dy: -1)
            } else {
                return false
            }
        }
        return true
    }

    var status: String {
        let index = hovered ?? selection
        guard entries.indices.contains(index) else { return "" }
        return "\(glyph(at: index))  \(entries[index].name)"
    }

    var hints: [KeyHint] {
        var hints = [
            KeyHint(keys: "↵", label: "Insert"),
            KeyHint(keys: "⌘↵", label: "Copy"),
        ]
        if isBrowsing {
            hints.append(KeyHint(keys: "⇥", label: "Next group"))
        }
        return hints
    }
}

struct EmojiPanelView: View {
    @ObservedObject var model: EmojiPanelController

    var body: some View {
        PanelChrome(
            query: $model.query,
            placeholder: "Search emoji",
            status: model.status,
            hints: model.hints,
            needsAccessibility: !model.canPaste,
            onFieldCreated: model.attach
        ) {
            GeometryReader { geometry in
                Group {
                    if model.rows.isEmpty {
                        EmptyState(
                            symbol: "face.dashed",
                            title: "No emoji found",
                            message: "Nothing matches “\(model.query)”. Try a shorter or different word."
                        )
                    } else {
                        grid
                    }
                }
                .onAppear { model.updateColumns(width: geometry.size.width) }
                .onChange(of: geometry.size.width) { _, width in
                    model.updateColumns(width: width)
                }
            }
        }
    }

    private var grid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: EmojiPanelController.spacing) {
                    ForEach(model.rows) { row in
                        switch row.kind {
                        case .header(let title):
                            Text(title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.leading, 4)
                                .padding(.top, 8)
                                .padding(.bottom, 2)
                                .accessibilityAddTraits(.isHeader)
                        case .cells(let range):
                            HStack(spacing: EmojiPanelController.spacing) {
                                ForEach(range, id: \.self) { index in
                                    cell(index)
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 4)
            }
            .onChange(of: model.scrollTarget) { _, target in
                guard let target else { return }
                proxy.scrollTo(target.rowID, anchor: target.anchor)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Emoji")
    }

    private func cell(_ index: Int) -> some View {
        let name = model.entries[index].name
        return EmojiCell(glyph: model.glyph(at: index), name: name, isSelected: index == model.selection)
            .equatable()
            .onHover { model.hover(index, $0) }
            .onTapGesture { model.insert(at: index) }
            .accessibilityAction { model.insert(at: index) }
    }
}

private struct EmojiCell: View, Equatable {
    let glyph: String
    let name: String
    let isSelected: Bool
    @State private var hovering = false

    nonisolated static func == (lhs: EmojiCell, rhs: EmojiCell) -> Bool {
        lhs.glyph == rhs.glyph && lhs.name == rhs.name && lhs.isSelected == rhs.isSelected
    }

    var body: some View {
        Text(glyph)
            .font(.system(size: 30))
            .frame(width: EmojiPanelController.cell, height: EmojiPanelController.cell)
            .background(SelectionBackground(isSelected: isSelected, isHovered: hovering))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .help(name)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(name)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
