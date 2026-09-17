import AppKit
import SwiftUI
import RotoCore

@MainActor
final class KeymapEditorController: ObservableObject {
    @Published var bindings: [KeymapBinding] = [] {
        didSet { saveError = nil }
    }
    @Published var query = ""
    @Published private(set) var recordingID: UUID?
    @Published private(set) var recordingError: String?
    @Published private(set) var saveError: String?
    @Published private(set) var loaded = false

    var popupScreen: PopupScreen = .primary
    var onRecordingChanged: ((Bool) -> Void)?
    var onSaved: (() -> Void)?
    private var source: String?
    private var config = Config()
    private var initialBindings: [KeymapBinding] = []
    private static let size = NSSize(width: 860, height: 620)

    private lazy var panel: FloatingPanel = {
        let panel = FloatingPanel(size: Self.size)
        let host = NSHostingView(rootView: KeymapEditorView(model: self))
        host.frame = NSRect(origin: .zero, size: Self.size)
        panel.embed(rootView: host)
        panel.onKeyDown = { [weak self] in self?.handleKey($0) ?? false }
        // Clicking away hides the popup, but keeps an unsaved draft until Save or Cancel.
        panel.onDismiss = { [weak self] in self?.stopRecording() }
        return panel
    }()

    var isRecording: Bool { recordingID != nil }
    var hasChanges: Bool { bindings != initialBindings }
    var windowActions: [String] { KeymapEditor.windowActions(in: config) }
    var availablePopups: [KeymapKind] {
        [.clipboard, .emoji, .windows, .cheatsheet].filter { kind in
            !bindings.contains { $0.kind == kind }
        }
    }
    var validationMessage: String? {
        guard loaded else { return nil }
        do {
            _ = try KeymapEditor.hotkeys(from: bindings, config: config)
            return nil
        } catch {
            return String(describing: error)
        }
    }
    var canSave: Bool { loaded && hasChanges && !isRecording && validationMessage == nil }

    func show() {
        if source == nil || !hasChanges { reload() }
        panel.present(screen: popupScreen)
    }

    func dismiss(animated: Bool = true) {
        stopRecording()
        panel.dismiss(animated: animated)
    }

    func reload() {
        stopRecording()
        loaded = false
        source = nil
        bindings = []
        initialBindings = []
        query = ""
        do {
            let text = try String(contentsOf: Paths.configFile, encoding: .utf8)
            config = try ConfigLoader.parse(text)
            bindings = KeymapEditor.bindings(in: config)
            initialBindings = bindings
            source = text
            loaded = true
        } catch {
            saveError = String(describing: error)
        }
    }

    func add(_ kind: KeymapKind) {
        stopRecording()
        query = ""
        let binding = KeymapBinding(kind: kind, shortcut: "", target: kind == .window ? "half-left" : "")
        bindings.append(binding)
        startRecording(binding.id)
    }

    func remove(_ id: UUID) {
        if recordingID == id { stopRecording() }
        bindings.removeAll { $0.id == id }
    }

    func startRecording(_ id: UUID) {
        guard loaded else { return }
        recordingError = nil
        recordingID = id
        onRecordingChanged?(true)
        panel.makeFirstResponder(nil)
    }

    func stopRecording() {
        recordingError = nil
        guard recordingID != nil else { return }
        recordingID = nil
        onRecordingChanged?(false)
    }

    func save() {
        guard canSave, let source else { return }
        do {
            try KeymapEditor.save(bindings, to: Paths.configFile, original: source)
            self.source = nil
            initialBindings = bindings
            onSaved?()
            dismiss()
        } catch {
            saveError = String(describing: error)
        }
    }

    func cancel() {
        bindings = initialBindings
        source = nil
        dismiss()
    }

    func openConfig() {
        dismiss(animated: false)
        NSWorkspace.shared.open(Paths.configFile)
    }

    func matches(_ binding: KeymapBinding) -> Bool {
        let text = [binding.kind.title, binding.target, binding.shortcut,
                    binding.kind == .window ? Cheatsheet.describe(windowAction: binding.target) : ""]
            .joined(separator: " ")
        return query.isEmpty || text.localizedStandardContains(query)
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let flags = PanelKey.modifiers(event)
        if let id = recordingID {
            if event.keyCode == PanelKey.escape, flags.isEmpty {
                stopRecording()
                return true
            }
            guard !event.isARepeat else { return true }
            var modifiers: UInt32 = 0
            if flags.contains(.control) { modifiers |= KeyCombo.controlBit }
            if flags.contains(.option) { modifiers |= KeyCombo.optionBit }
            if flags.contains(.shift) { modifiers |= KeyCombo.shiftBit }
            if flags.contains(.command) { modifiers |= KeyCombo.cmdBit }
            do {
                let combo = try KeyCombo.recorded(keyCode: UInt32(event.keyCode), carbonModifiers: modifiers)
                if let index = bindings.firstIndex(where: { $0.id == id }) {
                    bindings[index].shortcut = combo.canonical
                }
                stopRecording()
            } catch {
                recordingError = String(describing: error)
                Announcer.say(recordingError ?? "Invalid shortcut")
            }
            return true
        }
        if event.keyCode == PanelKey.escape, flags.isEmpty {
            cancel()
            return true
        }
        if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "s" {
            save()
            return true
        }
        return false
    }
}

private extension KeymapKind {
    var title: String {
        switch self {
        case .window: "Window"
        case .app: "App"
        case .clipboard: "Clipboard history"
        case .emoji: "Emoji picker"
        case .windows: "Window switcher"
        case .cheatsheet: "Cheatsheet"
        }
    }
}

private struct KeymapEditorView: View {
    @ObservedObject var model: KeymapEditorController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "keyboard")
                    .accessibilityHidden(true)
                Text("Customize Shortcuts")
                    .font(.system(size: 20, weight: .semibold))
                Spacer()
                Button("Open config…", action: model.openConfig)
            }
            Text("Edit every config keymap. Type a combo such as ctrl+alt+t, or record it. Changes apply only when saved.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            HStack {
                TextField("Filter shortcuts", text: $model.query)
                    .accessibilityLabel("Filter shortcuts")
                Button("Add Window") { model.add(.window) }
                Button("Add App") { model.add(.app) }
                Menu("Add Popup") {
                    ForEach(model.availablePopups, id: \.self) { kind in
                        Button(kind.title) { model.add(kind) }
                    }
                }
                .disabled(model.availablePopups.isEmpty)
                .fixedSize()
            }
            .disabled(!model.loaded || model.isRecording)

            Divider()
            if model.loaded {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach($model.bindings) { $binding in
                                if model.matches(binding) {
                                    KeymapEditorRow(binding: $binding, model: model)
                                        .id(binding.id)
                                }
                            }
                        }
                        .padding(2)
                    }
                    .onChange(of: model.recordingID) { _, id in
                        if let id { proxy.scrollTo(id, anchor: .center) }
                    }
                }
                if model.bindings.filter({ model.matches($0) }).isEmpty {
                    Text(model.bindings.isEmpty ? "No keymaps. Add a window, app, or popup shortcut above." : "No matching shortcuts.")
                        .foregroundStyle(.secondary)
                }
            } else {
                EmptyState(symbol: "exclamationmark.triangle", title: "Could not load config",
                           message: "Fix the config file, then reload. The active shortcuts have not changed.")
            }
            feedback
            Divider()
            HStack {
                Button("Discard & Reload", action: model.reload)
                    .disabled(model.isRecording)
                Text("⌘S to save · Esc to cancel")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", action: model.cancel)
                Button("Save", action: model.save)
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canSave)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var feedback: some View {
        if model.isRecording {
            HStack {
                Text(model.recordingError ?? "Press a shortcut with at least one modifier. Esc stops recording. roto’s hotkeys are paused.")
                Spacer()
                Button("Stop Recording", action: model.stopRecording)
            }
            .font(.system(size: 12))
            .foregroundStyle(.orange)
        } else if let error = model.saveError ?? model.validationMessage {
            ScrollView {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 65)
            .accessibilityLabel("Cannot save: \(error)")
        } else {
            Text(model.hasChanges ? "Unsaved changes · Clicking away keeps this draft. Cancel discards it." : "Saved in ~/.config/roto/config.toml")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}

private struct KeymapEditorRow: View {
    @Binding var binding: KeymapBinding
    @ObservedObject var model: KeymapEditorController

    var body: some View {
        HStack(spacing: 8) {
            Text(binding.kind == .window || binding.kind == .app ? binding.kind.title : "Popup")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
            target
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(model.isRecording)
            TextField("ctrl+alt+…", text: $binding.shortcut)
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 195)
                .accessibilityLabel("Shortcut for \(label)")
                .disabled(model.isRecording)
            Button(model.recordingID == binding.id ? "Listening…" : "Record") {
                model.startRecording(binding.id)
            }
            .frame(width: 80)
            .disabled(model.isRecording)
            .accessibilityLabel("Record shortcut for \(label)")
            Button {
                model.remove(binding.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Remove shortcut for \(label)")
            .help("Remove this keymap")
            .disabled(model.isRecording)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
    }

    private var label: String {
        switch binding.kind {
        case .window: Cheatsheet.describe(windowAction: binding.target)
        case .app: binding.target.isEmpty ? "app" : binding.target
        default: binding.kind.title
        }
    }

    @ViewBuilder private var target: some View {
        switch binding.kind {
        case .window:
            Picker("Window action", selection: $binding.target) {
                // Keep a valid hand-written action with surrounding whitespace selectable.
                if !model.windowActions.contains(binding.target) {
                    Text(Cheatsheet.describe(windowAction: binding.target.trimmingCharacters(in: .whitespacesAndNewlines)))
                        .tag(binding.target)
                }
                ForEach(model.windowActions, id: \.self) { action in
                    Text(Cheatsheet.describe(windowAction: action)).tag(action)
                }
            }
            .labelsHidden()
            .accessibilityLabel("Window action")
        case .app:
            TextField("Bundle ID, app name, or .app path", text: $binding.target)
                .accessibilityLabel("App target")
        default:
            Text(binding.kind.title)
                .font(.system(size: 13))
        }
    }
}
