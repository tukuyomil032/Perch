// perchTests/Vendor/NookSurfaceModificationsTests.swift
//
// Guards the changes Perch makes to the vendored NookSurface. Re-syncing with a newer
// upstream would silently drop them otherwise, and these are the kind of regression that
// only shows up as "the notch looks wrong" long after the merge.
//
// See perch/Vendor/NookSurface/README.md for what is modified and why.

import SwiftUI
import Testing

@testable import perch

@Suite("NookSurface Perch modifications")
@MainActor
struct NookSurfaceModificationsTests {

    // MARK: - .expandsOnHover

    @Test("expandsOnHover is a distinct option, not an alias of an existing one")
    func expandsOnHoverIsDistinct() {
        #expect(NookHoverBehavior.expandsOnHover != NookHoverBehavior.keepVisible)
        #expect(NookHoverBehavior.expandsOnHover != NookHoverBehavior.hapticFeedback)
        #expect(NookHoverBehavior.expandsOnHover.rawValue == 1 << 2)
    }

    @Test("all still enables hover expansion, keeping upstream defaults unchanged")
    func allIncludesExpandsOnHover() {
        #expect(NookHoverBehavior.all.contains(.expandsOnHover))
        #expect(NookHoverBehavior.all.contains(.keepVisible))
        #expect(NookHoverBehavior.all.contains(.hapticFeedback))
    }

    @Test("hover expansion can be opted out of without losing the other side-effects")
    func expansionIsOptional() {
        let quiet: NookHoverBehavior = [.keepVisible, .hapticFeedback]
        #expect(!quiet.contains(.expandsOnHover))
        #expect(quiet.contains(.keepVisible))
    }

    // MARK: - syntheticNotchWidth

    @Test("content is type-erased at the Nook boundary")
    func contentIsTypeErasedAtNookBoundary() {
        let nook = Nook(
            expanded: { Text("Expanded") },
            compactLeading: { Image(systemName: "chevron.left") },
            compactTrailing: { Color.clear }
        )

        #expect(type(of: nook.expandedContent) == AnyView.self)
        #expect(type(of: nook.compactLeadingContent) == AnyView.self)
        #expect(type(of: nook.compactTrailingContent) == AnyView.self)
    }

    @Test("synthetic notch defaults to real-notch dimensions, not the upstream 300pt")
    func syntheticNotchWidthDefault() {
        let nook = Nook(hoverBehavior: [.keepVisible]) { EmptyView() }
        // Real MacBook notches measure roughly 185-208pt. Upstream's 300pt placeholder
        // reads as obviously wrong next to one, which is why Perch overrides it.
        #expect(nook.syntheticNotchWidth == 195)
        #expect(nook.syntheticNotchWidth < 300)
    }

    @Test("synthetic notch width is settable by the host")
    func syntheticNotchWidthIsSettable() {
        let nook = Nook(hoverBehavior: [.keepVisible]) { EmptyView() }
        nook.syntheticNotchWidth = 208
        #expect(nook.syntheticNotchWidth == 208)
    }

    // MARK: - compact corner radii

    @Test("compact corner radii default to the historical hardcoded values")
    func compactCornerRadiiDefault() {
        let style = NookStyle(topCornerRadius: 15, bottomCornerRadius: 20)
        #expect(style.compactTopCornerRadius == 6)
        #expect(style.compactBottomCornerRadius == 14)
    }

    @Test("compact corner radii are settable independently of the expanded radii")
    func compactCornerRadiiAreSettable() {
        let style = NookStyle(
            topCornerRadius: 15,
            bottomCornerRadius: 20,
            compactTopCornerRadius: 10,
            compactBottomCornerRadius: 20
        )
        #expect(style.compactTopCornerRadius == 10)
        #expect(style.compactBottomCornerRadius == 20)
        #expect(style.topCornerRadius == 15)
        #expect(style.bottomCornerRadius == 20)
    }

    // MARK: - published notch metrics

    @Test("notch metrics are readable by the host")
    func notchMetricsArePublic() {
        // A hidden nook has not resolved a screen yet, so the values are still zero.
        // What matters here is that they are reachable at all — upstream keeps both
        // internal, and Perch sizes its own compact slots against them.
        let nook = Nook(hoverBehavior: [.keepVisible]) { EmptyView() }
        #expect(nook.notchSize == .zero)
        #expect(nook.menubarHeight == 0)
    }
}
