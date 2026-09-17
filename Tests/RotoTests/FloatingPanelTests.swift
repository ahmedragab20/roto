import AppKit
import SwiftUI
import Testing
@testable import Roto

@MainActor
struct FloatingPanelTests {
    @Test(arguments: [false, true])
    func scrollableContentCannotGrowPanel(includeChrome: Bool) {
        _ = NSApplication.shared
        let requestedSize = NSSize(width: 780, height: 520)
        let panel = FloatingPanel(size: requestedSize)
        let hosting = NSHostingView(rootView: PopupTestContent(count: 4, showBanner: false, includeChrome: includeChrome))
        panel.embed(rootView: hosting)

        for (count, showBanner) in [(4, false), (80, true), (1, false)] {
            hosting.rootView = PopupTestContent(count: count, showBanner: showBanner, includeChrome: includeChrome)
            hosting.invalidateIntrinsicContentSize()
            panel.contentView?.layoutSubtreeIfNeeded()
            panel.layoutIfNeeded()

            // Neither the actual viewport nor the minimum size advertised to AppKit may grow.
            #expect(panel.frame.size == requestedSize)
            #expect(panel.contentView?.bounds.size == requestedSize)
            #expect(hosting.frame.size == requestedSize)
            #expect(hosting.fittingSize.width <= requestedSize.width)
            #expect(hosting.fittingSize.height <= requestedSize.height)
            #expect(panel.contentView!.fittingSize.width <= requestedSize.width)
            #expect(panel.contentView!.fittingSize.height <= requestedSize.height)
        }
        if #available(macOS 26.0, *) {
            #expect(panel.contentView is NSGlassEffectView)
        }
    }
}

private struct PopupTestContent: View {
    let count: Int
    let showBanner: Bool
    let includeChrome: Bool

    var body: some View {
        if includeChrome {
            PanelChrome(
                query: .constant(""),
                placeholder: "Search test items",
                status: "\(count) items",
                hints: [],
                needsAccessibility: showBanner,
                onFieldCreated: { _ in }
            ) {
                rows
            }
        } else {
            rows
        }
    }

    private var rows: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(0..<count, id: \.self) { index in
                    Text("History row \(index)")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
        }
    }
}
