import AppKit
import SwiftUI
import RotoCore

@MainActor
final class WindowSwitcherController: NSObject, ObservableObject {
    @Published var query = "" {
        didSet {
            if query != oldValue {
                userMoved = false
                applyFilter(keepSelection: false)
            }
        }
    }
    @Published private(set) var results: [WindowEntry] = []
    @Published private(set) var selection = 0
    @Published private(set) var canControl = true
    @Published private(set) var isLoading = false
    @Published private(set) var previewsAllowed = false
    @Published private(set) var scrollToTop = 0

    var popupScreen: PopupScreen = .primary
    let previews = WindowPreviews()
    private var all: [WindowEntry] = []
    private var elements: [String: AXWindowRef] = [:]
    private var refreshGeneration = 0
    /// Once the user moves the selection, refreshes keep it instead of preselecting.
    private var userMoved = false
    private weak var searchField: NSTextField?
    private var warmWork: DispatchWorkItem?

    private static let size = NSSize(width: 840, height: 520)

    private lazy var panel: FloatingPanel = {
        let panel = FloatingPanel(size: Self.size)
        let host = NSHostingView(rootView: WindowSwitcherView(model: self))
        host.frame = NSRect(origin: .zero, size: Self.size)
        panel.embed(rootView: host)
        panel.onKeyDown = { [weak self] event in
            self?.handleKey(event) ?? false
        }
        panel.onDismiss = { [weak self] in
            self?.query = ""
            // Captures are only good for one showing; don't hold them while hidden.
            self?.previews.reset()
        }
        return panel
    }()

    var isVisible: Bool { panel.isShown }

    var selectedEntry: WindowEntry? {
        results.indices.contains(selection) ? results[selection] : nil
    }

    func prepare() {
        panel.contentView?.layoutSubtreeIfNeeded()
        // Reading every app's windows takes long enough to see. Without a list
        // that is already current, the popup opens on the previous one and
        // reshuffles a frame later — and ↩ pressed in that frame picks the wrong
        // window. Switching apps is what reorders it, so that is when it is reread.
        for name in [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ] {
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleWarm() }
            }
        }
        scheduleWarm()
    }

    /// Rereads the window list once the user has settled on an app, never while
    /// the popup is up (it does its own refresh then).
    private func scheduleWarm() {
        warmWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.panel.isShown else { return }
            self.refresh(keepSelection: false)
        }
        warmWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func toggle() {
        if panel.isShown {
            panel.dismiss()
        } else {
            show()
        }
    }

    func show() {
        canControl = AXSupport.isTrusted
        previewsAllowed = previews.isAllowed
        previews.reset()
        query = ""
        userMoved = false
        // Last known list for an instant open; the fresh one replaces it a moment later.
        applyFilter(keepSelection: false)
        panel.focusView = searchField
        panel.present(screen: popupScreen)
        // Asking macOS costs a round trip to the permission daemon; do it after
        // the window is up rather than in front of it.
        PermissionCache.refresh { [weak self] permissions in
            self?.previewsAllowed = permissions.canCaptureScreen
        }
        refresh(keepSelection: false)
    }

    func dismiss(animated: Bool = true) {
        panel.dismiss(animated: animated)
    }

    func attach(_ field: NSTextField) {
        searchField = field
        PanelFocus.focusWhenReady(field)
    }

    func enablePreviews() {
        previews.requestAccess()
    }

    // MARK: - Actions

    func select(_ index: Int) {
        guard results.indices.contains(index), index != selection else { return }
        selection = index
        userMoved = true
        if let entry = selectedEntry {
            Announcer.say(WindowText.title(for: entry) + ", " + entry.appName)
        }
    }

    func activate(at index: Int) {
        guard results.indices.contains(index) else { return }
        let entry = results[index]
        let element = elements[entry.id]?.element
        panel.dismiss(animated: false)
        if let element {
            WindowFocus.focus(element, pid: entry.pid)
        } else if let app = NSRunningApplication(processIdentifier: entry.pid) {
            if let url = app.bundleURL, entry.isAppOnly {
                // No window on this Space: let macOS jump to one or open a new one.
                WindowFocus.open(url)
            } else {
                WindowFocus.activate(app)
            }
        }
    }

    func closeSelected() {
        guard let entry = selectedEntry, let element = elements[entry.id]?.element else {
            NSSound.beep()
            return
        }
        if WindowFocus.close(element) {
            refreshSoon()
        } else {
            NSSound.beep()
        }
    }

    func toggleMinimizedSelected() {
        guard let entry = selectedEntry, let element = elements[entry.id]?.element,
              WindowFocus.toggleMinimized(element)
        else {
            NSSound.beep()
            return
        }
        refreshSoon()
    }

    func hideSelectedApp() {
        guard let entry = selectedEntry, let app = NSRunningApplication(processIdentifier: entry.pid) else { return }
        if app.isHidden {
            app.unhide()
        } else {
            app.hide()
        }
        refreshSoon()
    }

    func quitSelectedApp() {
        guard let entry = selectedEntry, let app = NSRunningApplication(processIdentifier: entry.pid) else { return }
        app.terminate()
        refreshSoon(after: 0.6)
    }

    private func refreshSoon(after delay: TimeInterval = 0.25) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.panel.isShown else { return }
            self.refresh(keepSelection: true)
        }
    }

    private func refresh(keepSelection: Bool) {
        refreshGeneration += 1
        let generation = refreshGeneration
        let apps = WindowCatalog.runningApps()
        isLoading = all.isEmpty
        Task { [weak self] in
            // AX reads block on each app; keep them off the main thread.
            let snapshot = await Task.detached(priority: .userInitiated) {
                WindowCatalog.snapshot(apps: apps)
            }.value
            guard let self, generation == self.refreshGeneration else { return }
            self.elements = snapshot.elements
            if self.isLoading {
                self.isLoading = false
            }
            // Nothing moved: leave the list as it is rather than republishing an
            // identical one and making every visible row rebuild itself.
            let sorted = WindowList.sorted(snapshot.entries)
            guard sorted != self.all else { return }
            self.all = sorted
            self.applyFilter(keepSelection: keepSelection || self.userMoved)
        }
    }

    private func applyFilter(keepSelection: Bool) {
        let previous = selectedEntry?.id
        results = WindowList.filtered(all, query: query)
        if keepSelection, let previous, let index = results.firstIndex(where: { $0.id == previous }) {
            selection = index
        } else if keepSelection {
            selection = min(selection, max(results.count - 1, 0))
        } else {
            selection = WindowList.initialSelection(results, query: query)
            scrollToTop += 1
        }
    }

    private func move(by delta: Int) {
        guard !results.isEmpty else { return }
        select(min(max(selection + delta, 0), results.count - 1))
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
            activate(at: selection)
        case (PanelKey.escape, []):
            if query.isEmpty {
                panel.dismiss()
            } else {
                query = ""
            }
        default:
            let letter = PanelKey.letter(event)
            if modifiers == .command, let digit = PanelKey.digits[event.keyCode] {
                activate(at: digit - 1)
            } else if modifiers == .control, letter == "n" {
                move(by: 1)
            } else if modifiers == .control, letter == "p" {
                move(by: -1)
            } else if modifiers == .command, letter == "w" {
                closeSelected()
            } else if modifiers == .command, letter == "m" {
                toggleMinimizedSelected()
            } else if modifiers == .command, letter == "h" {
                hideSelectedApp()
            } else if modifiers == .command, letter == "q" {
                quitSelectedApp()
            } else {
                return false
            }
        }
        return true
    }

    var status: String {
        let windows = all.filter { !$0.isAppOnly }.count
        let label = windows == 1 ? "1 window" : "\(windows) windows"
        return query.isEmpty ? label : "\(results.count) matches · \(label)"
    }

    var hints: [KeyHint] {
        [
            KeyHint(keys: "↵", label: "Switch"),
            KeyHint(keys: "⌘W", label: "Close"),
            KeyHint(keys: "⌘M", label: "Minimize"),
            KeyHint(keys: "⌘H", label: "Hide app"),
            KeyHint(keys: "⌘Q", label: "Quit app"),
        ]
    }
}

// MARK: - Views

struct WindowSwitcherView: View {
    @ObservedObject var model: WindowSwitcherController

    var body: some View {
        PanelChrome(
            query: $model.query,
            placeholder: "Search windows and apps",
            status: model.status,
            hints: model.hints,
            needsAccessibility: !model.canControl,
            onFieldCreated: model.attach
        ) {
            if model.results.isEmpty {
                if model.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    EmptyState(
                        symbol: "macwindow.on.rectangle",
                        title: model.query.isEmpty ? "No windows" : "No matches",
                        message: model.query.isEmpty
                            ? "No app windows are open on this Space."
                            : "No window or app matches “\(model.query)”."
                    )
                }
            } else {
                HStack(spacing: 12) {
                    list
                        .frame(width: 340)
                    Divider()
                    WindowInspector(entry: model.selectedEntry, model: model)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(model.results.enumerated()), id: \.element.id) { index, entry in
                        WindowRow(entry: entry, isSelected: index == model.selection, shortcut: index < 9 ? index + 1 : nil)
                            .equatable()
                            .id(entry.id)
                            .onTapGesture(count: 2) {
                                model.activate(at: index)
                            }
                            .simultaneousGesture(TapGesture().onEnded {
                                model.select(index)
                            })
                            .accessibilityAction {
                                model.activate(at: index)
                            }
                    }
                }
                .padding(.vertical, 2)
            }
            .onChange(of: model.selection) { _, _ in
                if let id = model.selectedEntry?.id {
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
        .accessibilityLabel("Windows")
    }
}

private struct WindowRow: View, Equatable {
    let entry: WindowEntry
    let isSelected: Bool
    let shortcut: Int?
    @State private var hovering = false

    /// Moving the selection must not rebuild every visible row, only the two
    /// that changed; hover is this row's own state and drives itself.
    nonisolated static func == (lhs: WindowRow, rhs: WindowRow) -> Bool {
        lhs.entry == rhs.entry && lhs.isSelected == rhs.isSelected && lhs.shortcut == rhs.shortcut
    }

    var body: some View {
        HStack(spacing: 10) {
            AppIconView(bundleID: entry.bundleID, pid: entry.pid)
                .frame(width: 28, height: 28)
                .opacity(entry.isMinimized || entry.isAppHidden || entry.isAppOnly ? 0.55 : 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(WindowText.title(for: entry))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(entry.isAppOnly ? .secondary : .primary)
                    .lineLimit(1)
                Text(WindowText.subtitle(for: entry))
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
        .accessibilityLabel("\(WindowText.title(for: entry)), \(WindowText.subtitle(for: entry))")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

private struct WindowInspector: View {
    let entry: WindowEntry?
    @ObservedObject var model: WindowSwitcherController

    var body: some View {
        if let entry {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    AppIconView(bundleID: entry.bundleID, pid: entry.pid)
                        .frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(WindowText.title(for: entry))
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(2)
                        Text(entry.appName)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }

                preview(for: entry)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(entry.id)

                details(for: entry)

                if !model.previewsAllowed {
                    Button("Show live window previews…") {
                        model.enablePreviews()
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
                    .help("Needs Screen Recording permission. roto only captures the selected window, locally.")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Window details")
        }
    }

    @ViewBuilder
    private func preview(for entry: WindowEntry) -> some View {
        if model.previewsAllowed, let id = entry.windowID, !entry.isMinimized, !entry.isAppHidden {
            WindowThumbnail(windowID: id, previews: model.previews) {
                WindowMap(frame: entry.frame)
            }
        } else {
            WindowMap(frame: entry.frame)
        }
    }

    private func details(for entry: WindowEntry) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            if let frame = entry.frame {
                detail("Size", "\(Int(frame.width)) × \(Int(frame.height))")
                detail("Position", "\(Int(frame.minX)), \(Int(frame.minY))")
                if let display = WindowText.displayName(for: frame) {
                    detail("Display", display)
                }
            }
            detail("State", WindowText.state(for: entry))
        }
        .font(.system(size: 11))
    }

    private func detail(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct WindowThumbnail<Placeholder: View>: View {
    let windowID: CGWindowID
    let previews: WindowPreviews
    @ViewBuilder var placeholder: () -> Placeholder
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(radius: 4, y: 1)
                    .accessibilityLabel("Window preview")
            } else {
                placeholder()
            }
        }
        .task(id: windowID) {
            image = previews.cached(windowID)
            if image == nil {
                image = await previews.image(for: windowID)
            }
        }
    }
}

/// Where the window sits across all displays; needs no extra permission.
private struct WindowMap: View {
    let frame: CGRect?

    var body: some View {
        let screens = NSScreen.screens.map(\.frame)
        let primaryMaxY = NSScreen.screens.first { $0.frame.origin == .zero }?.frame.maxY ?? 0
        let window = frame.map { Geometry.axToCocoa($0, primaryMaxY: primaryMaxY) }
        let accent = Color(nsColor: .controlAccentColor)
        Canvas { context, size in
            let bounds = screens.reduce(CGRect.null) { $0.union($1) }
            guard !bounds.isNull, bounds.width > 0, bounds.height > 0 else { return }
            let scale = min((size.width - 8) / bounds.width, (size.height - 8) / bounds.height)
            let dx = (size.width - bounds.width * scale) / 2
            let dy = (size.height - bounds.height * scale) / 2
            func place(_ rect: CGRect) -> CGRect {
                CGRect(
                    x: (rect.minX - bounds.minX) * scale + dx,
                    y: (bounds.maxY - rect.maxY) * scale + dy,
                    width: rect.width * scale,
                    height: rect.height * scale
                )
            }
            for screen in screens {
                let path = Path(roundedRect: place(screen), cornerRadius: 4)
                context.fill(path, with: .color(.primary.opacity(0.06)))
                context.stroke(path, with: .color(.primary.opacity(0.25)), lineWidth: 1)
            }
            if let window {
                let path = Path(roundedRect: place(window).insetBy(dx: 1, dy: 1), cornerRadius: 3)
                context.fill(path, with: .color(accent.opacity(0.3)))
                context.stroke(path, with: .color(accent), lineWidth: 1.5)
            }
        }
        .accessibilityLabel(window == nil ? "Window position unknown" : "Window position on displays")
    }
}

private struct AppIconView: View {
    let bundleID: String?
    let pid: pid_t

    var body: some View {
        if let icon = AppIcons.icon(bundleID: bundleID) ?? NSRunningApplication(processIdentifier: pid)?.icon {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "app")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }
}

@MainActor
enum WindowText {
    static func title(for entry: WindowEntry) -> String {
        if entry.isAppOnly {
            return entry.appName
        }
        let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "\(entry.appName) window" : title
    }

    static func subtitle(for entry: WindowEntry) -> String {
        if entry.isAppOnly {
            return entry.isAppHidden ? "Hidden · no windows on this Space" : "No windows on this Space"
        }
        var parts = [entry.appName]
        let state = badges(for: entry)
        if !state.isEmpty {
            parts.append(state.joined(separator: ", "))
        }
        return parts.joined(separator: " · ")
    }

    static func state(for entry: WindowEntry) -> String {
        let state = badges(for: entry)
        return state.isEmpty ? "Open" : state.joined(separator: ", ")
    }

    static func displayName(for frame: CGRect) -> String? {
        let primaryMaxY = NSScreen.screens.first { $0.frame.origin == .zero }?.frame.maxY ?? 0
        let cocoa = Geometry.axToCocoa(frame, primaryMaxY: primaryMaxY)
        let screens = NSScreen.screens
        guard let index = Geometry.displayIndex(containing: cocoa, frames: screens.map(\.frame)) else { return nil }
        return screens[index].localizedName
    }

    private static func badges(for entry: WindowEntry) -> [String] {
        var badges: [String] = []
        if entry.isFocused { badges.append("Current") }
        if entry.isFullScreen { badges.append("Full screen") }
        if entry.isMinimized { badges.append("Minimized") }
        if entry.isAppHidden { badges.append("App hidden") }
        return badges
    }
}
