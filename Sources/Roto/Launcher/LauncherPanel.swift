import AppKit
import SwiftUI
import RotoCore

/// The app search popup: type part of an app's name, press ↩ to open it.
@MainActor
final class LauncherController: NSObject, ObservableObject {
    @Published var query = "" {
        didSet {
            if query != oldValue { runSearch() }
        }
    }
    @Published private(set) var results: [AppRecord] = []
    @Published private(set) var selection = 0
    @Published private(set) var scrollToTop = 0
    @Published private(set) var running: Set<String> = []

    var popupScreen: PopupScreen = .primary
    let search: AppSearch
    private weak var searchField: NSTextField?

    /// Rows shown for a query; an empty query lists every app.
    private static let limit = 40
    private static let size = NSSize(width: 680, height: 460)

    private lazy var panel: FloatingPanel = {
        let panel = FloatingPanel(size: Self.size)
        let host = NSHostingView(rootView: LauncherView(model: self))
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

    init(search: AppSearch = AppSearch()) {
        self.search = search
        super.init()
    }

    var isVisible: Bool { panel.isShown }

    var selectedApp: AppRecord? {
        results.indices.contains(selection) ? results[selection] : nil
    }

    /// Indexes apps and builds the popup now, so the first hotkey press is instant.
    func prepare() {
        search.refresh { [weak self] _ in
            self?.runSearch()
        }
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
        query = ""
        running = Self.runningPaths()
        runSearch()
        panel.focusView = searchField
        panel.present(screen: popupScreen)
        // Apps installed or removed since the last showing turn up a moment later.
        search.refresh { [weak self] changed in
            guard let self, changed, self.panel.isShown else { return }
            self.runSearch(keepSelection: true)
        }
    }

    func dismiss(animated: Bool = true) {
        panel.dismiss(animated: animated)
    }

    func attach(_ field: NSTextField) {
        searchField = field
        PanelFocus.focusWhenReady(field)
    }

    // MARK: - Actions

    func select(_ index: Int) {
        guard results.indices.contains(index), index != selection else { return }
        selection = index
        if let app = selectedApp {
            Announcer.say(app.name)
        }
    }

    func open(at index: Int) {
        guard results.indices.contains(index) else {
            NSSound.beep()
            return
        }
        let app = results[index]
        panel.dismiss(animated: false)
        search.recordLaunch(app)
        // Like a Dock click: launches it, or brings it forward with a window.
        WindowFocus.open(URL(fileURLWithPath: app.path))
    }

    func revealSelected() {
        guard let app = selectedApp else {
            NSSound.beep()
            return
        }
        panel.dismiss(animated: false)
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.path)])
    }

    private func runSearch(keepSelection: Bool = false) {
        let previous = keepSelection ? selectedApp?.path : nil
        results = search.search(query, limit: SearchQuery(query).isEmpty ? .max : Self.limit)
        if let previous, let index = results.firstIndex(where: { $0.path == previous }) {
            selection = index
        } else {
            selection = 0
            scrollToTop += 1
        }
    }

    private func move(by delta: Int) {
        guard !results.isEmpty else { return }
        select(min(max(selection + delta, 0), results.count - 1))
    }

    private static func runningPaths() -> Set<String> {
        var paths: Set<String> = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let url = app.bundleURL else { continue }
            paths.insert(url.path)
            paths.insert(url.resolvingSymlinksInPath().path)
        }
        return paths
    }

    func isRunning(_ app: AppRecord) -> Bool {
        running.contains(app.path) || running.contains(app.resolvedPath)
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
            move(by: -7)
        case (PanelKey.pageDown, _):
            move(by: 7)
        case (PanelKey.returnKey, []), (PanelKey.keypadEnter, []):
            open(at: selection)
        case (PanelKey.returnKey, .command), (PanelKey.keypadEnter, .command):
            revealSelected()
        case (PanelKey.escape, []):
            if query.isEmpty {
                panel.dismiss()
            } else {
                query = ""
            }
        default:
            let letter = PanelKey.letter(event)
            if modifiers == .command, let digit = PanelKey.digits[event.keyCode] {
                open(at: digit - 1)
            } else if modifiers == .control, letter == "n" {
                move(by: 1)
            } else if modifiers == .control, letter == "p" {
                move(by: -1)
            } else {
                return false
            }
        }
        return true
    }

    var status: String {
        if SearchQuery(query).isEmpty {
            let count = results.count
            return count == 1 ? "1 app" : "\(count) apps"
        }
        return results.count == 1 ? "1 match" : "\(results.count) matches"
    }

    var hints: [KeyHint] {
        [
            KeyHint(keys: "↵", label: "Open"),
            KeyHint(keys: "⌘↵", label: "Show in Finder"),
            KeyHint(keys: "⌘1–9", label: "Open result"),
        ]
    }
}

// MARK: - Views

struct LauncherView: View {
    @ObservedObject var model: LauncherController

    var body: some View {
        PanelChrome(
            query: $model.query,
            placeholder: "Search apps",
            status: model.status,
            hints: model.hints,
            needsAccessibility: false,
            onFieldCreated: model.attach
        ) {
            if model.results.isEmpty {
                if SearchQuery(model.query).isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    EmptyState(
                        symbol: "square.grid.3x3",
                        title: "No apps found",
                        message: "No installed app matches “\(model.query)”."
                    )
                }
            } else {
                list
            }
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(model.results.enumerated()), id: \.element.path) { index, app in
                        LauncherRow(
                            app: app,
                            isSelected: index == model.selection,
                            isRunning: model.isRunning(app),
                            shortcut: index < 9 ? index + 1 : nil
                        )
                        .equatable()
                        .id(app.path)
                        .onTapGesture {
                            model.open(at: index)
                        }
                        .accessibilityAction {
                            model.open(at: index)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .onChange(of: model.selection) { _, _ in
                if let path = model.selectedApp?.path {
                    proxy.scrollTo(path)
                }
            }
            .onChange(of: model.scrollToTop) { _, _ in
                if let path = model.results.first?.path {
                    proxy.scrollTo(path, anchor: .top)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Apps")
    }
}

private struct LauncherRow: View, Equatable {
    let app: AppRecord
    let isSelected: Bool
    let isRunning: Bool
    let shortcut: Int?
    @State private var hovering = false

    /// Moving the selection rebuilds only the two rows that changed.
    nonisolated static func == (lhs: LauncherRow, rhs: LauncherRow) -> Bool {
        lhs.app == rhs.app && lhs.isSelected == rhs.isSelected
            && lhs.isRunning == rhs.isRunning && lhs.shortcut == rhs.shortcut
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: AppIcons.icon(path: app.path))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
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
        .padding(.vertical, 5)
        .background(SelectionBackground(isSelected: isSelected, isHovered: hovering))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help(app.path)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(app.name), \(subtitle)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var subtitle: String {
        let folder = ((app.path as NSString).deletingLastPathComponent as NSString).abbreviatingWithTildeInPath
        return isRunning ? "Running · \(folder)" : folder
    }
}
