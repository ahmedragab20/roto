import AppKit
import SwiftUI
import RotoCore

@MainActor
final class CheatsheetController: NSObject, ObservableObject {
    @Published var query = "" {
        didSet {
            if query != oldValue { applyFilter() }
        }
    }
    @Published private(set) var sections: [ShortcutSection] = []
    @Published private(set) var scrollToTop = 0

    var popupScreen: PopupScreen = .primary
    /// The config in effect (the last one that loaded without errors).
    var config: () -> Config = { ConfigLoader.builtin }
    var onCustomize: (() -> Void)?
    private var allSections: [ShortcutSection] = []
    private var appNames: [String: String] = [:]

    private static let size = NSSize(width: 660, height: 600)

    private lazy var panel: FloatingPanel = {
        let panel = FloatingPanel(size: Self.size)
        let host = NSHostingView(rootView: CheatsheetView(model: self))
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

    var isVisible: Bool { panel.isShown }

    var shortcutCount: Int {
        sections.reduce(0) { $0 + $1.entries.count }
    }

    func prepare() {
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
        allSections = Cheatsheet.sections(for: config())
        appNames = [:]
        for entry in allSections.flatMap(\.entries) {
            if let target = entry.appTarget {
                appNames[target] = Self.appName(for: target)
            }
        }
        query = ""
        applyFilter()
        panel.present(screen: popupScreen)
    }

    func dismiss(animated: Bool = true) {
        panel.dismiss(animated: animated)
    }

    func attach(_ field: NSTextField) {
        PanelFocus.focusWhenReady(field)
    }

    func appName(for target: String) -> String {
        appNames[target] ?? target
    }

    func customize() {
        onCustomize?()
    }

    private func applyFilter() {
        let prepared = SearchQuery(query)
        if prepared.isEmpty {
            sections = allSections
        } else {
            sections = allSections.compactMap { section in
                // Searching a section name ("emoji", "focus") shows the whole section.
                if Fuzzy.score(prepared, fields: [SearchField(section.title, fuzzy: false)]) != nil {
                    return section
                }
                let entries = section.entries.filter { entry in
                    var fields = [SearchField(entry.title)]
                    if let combo = entry.combo {
                        fields.append(SearchField(combo.replacingOccurrences(of: "+", with: " "), fuzzy: false, isPrimary: false))
                    }
                    if let target = entry.appTarget {
                        fields.append(SearchField(appName(for: target)))
                    }
                    return Fuzzy.score(prepared, fields: fields) != nil
                }
                return entries.isEmpty ? nil : ShortcutSection(title: section.title, entries: entries)
            }
        }
        scrollToTop += 1
    }

    func handleKey(_ event: NSEvent) -> Bool {
        let modifiers = PanelKey.modifiers(event)
        if event.keyCode == PanelKey.escape, modifiers.isEmpty {
            if query.isEmpty {
                panel.dismiss()
            } else {
                query = ""
            }
            return true
        }
        if modifiers == .command, event.charactersIgnoringModifiers == "," {
            customize()
            return true
        }
        return false
    }

    private static func appName(for target: String) -> String {
        let fileManager = FileManager.default
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target) {
            return fileManager.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return (target as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
    }
}

struct CheatsheetView: View {
    @ObservedObject var model: CheatsheetController

    var body: some View {
        PanelChrome(
            query: $model.query,
            placeholder: "Search shortcuts",
            status: model.shortcutCount == 1 ? "1 shortcut" : "\(model.shortcutCount) shortcuts",
            hints: [KeyHint(keys: "⌘,", label: "Customize"), KeyHint(keys: "esc", label: "Close")],
            needsAccessibility: false,
            onFieldCreated: model.attach
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Current shortcuts")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Customize Shortcuts…", action: model.customize)
                }
                shortcutList
            }
        }
    }

    @ViewBuilder private var shortcutList: some View {
        if model.sections.isEmpty {
            EmptyState(
                symbol: "keyboard",
                title: "No matches",
                message: "No shortcut matches “\(model.query)”."
            )
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(model.sections) { section in
                            CheatsheetSection(section: section, model: model)
                                .id(section.id)
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.trailing, 8)
                }
                .onChange(of: model.scrollToTop) { _, _ in
                    if let first = model.sections.first {
                        proxy.scrollTo(first.id, anchor: .top)
                    }
                }
            }
        }
    }
}

private struct CheatsheetSection: View {
    let section: ShortcutSection
    @ObservedObject var model: CheatsheetController

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(section.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
                .padding(.bottom, 2)
                .accessibilityAddTraits(.isHeader)
            ForEach(section.entries) { entry in
                HStack(spacing: 12) {
                    Text(entry.keys)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.primary.opacity(0.08))
                        )
                        .frame(width: 150, alignment: .trailing)
                    if let target = entry.appTarget {
                        if let icon = CheatsheetIcons.icon(for: target) {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 18, height: 18)
                                .accessibilityHidden(true)
                        }
                        Text("Open \(model.appName(for: target))")
                            .font(.system(size: 13))
                    } else {
                        Text(entry.title)
                            .font(.system(size: 13))
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel(for: entry))
            }
        }
    }

    private func accessibilityLabel(for entry: ShortcutEntry) -> String {
        let action = entry.appTarget.map { "Open \(model.appName(for: $0))" } ?? entry.title
        return "\(action): \(entry.combo ?? entry.keys)"
    }
}

@MainActor
enum CheatsheetIcons {
    static func icon(for target: String) -> NSImage? {
        if let icon = AppIcons.icon(bundleID: target) {
            return icon
        }
        let name = (target as NSString).lastPathComponent.lowercased().replacingOccurrences(of: ".app", with: "")
        let app = NSWorkspace.shared.runningApplications.first { $0.localizedName?.lowercased() == name }
        return app?.icon
    }
}
