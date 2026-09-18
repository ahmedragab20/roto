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
            #expect(panel.contentFrame.size == requestedSize)
            #expect(panel.popupView?.bounds.size == requestedSize)
            #expect(hosting.frame.size == requestedSize)
            #expect(hosting.fittingSize.width <= requestedSize.width)
            #expect(hosting.fittingSize.height <= requestedSize.height)
            #expect(panel.popupView!.fittingSize.width <= requestedSize.width)
            #expect(panel.popupView!.fittingSize.height <= requestedSize.height)
        }
        if #available(macOS 26.0, *) {
            #expect(panel.popupView is NSGlassEffectView)
        }
    }

    /// ⌘Y on an entry with nothing to preview must not leave the popup believing a
    /// preview is open: that belief is what every auto-close path checks before it
    /// closes the popup, so a stuck one made the popup impossible to dismiss.
    @Test func quickLookStaysClosedWhenThereIsNothingToPreview() {
        _ = NSApplication.shared
        let panel = FloatingPanel(size: NSSize(width: 400, height: 300))
        panel.embed(rootView: NSHostingView(rootView: Color.clear))

        #expect(panel.isQuickLookOpen == false)
        #expect(panel.hideQuickLook() == false)

        panel.showQuickLook([])
        #expect(panel.isQuickLookOpen == false)
        #expect(panel.hideQuickLook() == false)
    }

    /// A preview asked for but dismissed before it appeared still has to be closed,
    /// or it is left behind on screen after the popup that owns it has gone.
    @Test func quickLookOpenedButNotYetVisibleIsStillClosed() {
        _ = NSApplication.shared
        let panel = FloatingPanel(size: NSSize(width: 400, height: 300))
        panel.embed(rootView: NSHostingView(rootView: Color.clear))

        panel.showQuickLook([URL(fileURLWithPath: "/System/Library/CoreServices/SystemVersion.plist")])
        // Open as far as this popup is concerned, whether or not it has appeared.
        #expect(panel.isQuickLookOpen)

        #expect(panel.hideQuickLook())
        #expect(panel.isQuickLookOpen == false)
    }

    /// The material must sit inside a transparent margin, or its shadow and edge
    /// lighting render against the window's square edge and block out the corners.
    @Test func popupLeavesRoomAroundItselfForTheMaterialsShadow() {
        _ = NSApplication.shared
        let requestedSize = NSSize(width: 780, height: 520)
        let panel = FloatingPanel(size: requestedSize)
        panel.embed(rootView: NSHostingView(rootView: Color.clear))

        let inset = FloatingPanel.contentInset
        #expect(panel.frame.width == requestedSize.width + inset * 2)
        #expect(panel.frame.height == requestedSize.height + inset * 2)
        #expect(panel.contentFrame.size == requestedSize)
        // The margin is part of the window but never part of the popup.
        #expect(panel.frame.contains(panel.contentFrame))
        if #available(macOS 26.0, *) {
            #expect(inset > 0)
            #expect(panel.hasShadow == false)
            #expect((panel.popupView as? NSGlassEffectView)?.cornerRadius == 24)
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
