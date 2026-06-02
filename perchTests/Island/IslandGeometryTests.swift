import AppKit
import Testing

@testable import perch

@MainActor
struct IslandGeometryTests {
    @Test func compactFrameFloatingPillHasCorrectHeight() {
        guard let screen = NSScreen.main else { return }
        let frame = IslandGeometry.compactFrame(mode: .floatingPill, screen: screen)
        #expect(frame.height == 34)
    }

    @Test func compactFrameFloatingPillMinWidth() {
        guard let screen = NSScreen.main else { return }
        let frame = IslandGeometry.compactFrame(mode: .floatingPill, screen: screen)
        #expect(frame.width >= 150)
    }

    @Test func expandedFrameIsWiderThanCompact() {
        guard let screen = NSScreen.main else { return }
        let compact = IslandGeometry.compactFrame(mode: .floatingPill, screen: screen)
        let expanded = IslandGeometry.expandedFrame(mode: .floatingPill, screen: screen)
        #expect(expanded.width > compact.width)
        #expect(expanded.height > compact.height)
    }

    @Test func physicalNotchCompactUsesNotchDimensions() {
        guard let screen = NSScreen.main else { return }
        let notchSize = CGSize(width: 200, height: 34)
        let frame = IslandGeometry.compactFrame(mode: .physicalNotch(notchSize: notchSize), screen: screen)
        #expect(frame.width >= notchSize.width)
        #expect(frame.height >= notchSize.height)
    }
}
