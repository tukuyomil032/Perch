import Testing
@testable import perch
import AppKit

@MainActor
struct IslandGeometryTests {
    let screen = NSScreen.main!

    @Test func compactFrameFloatingPillHasCorrectHeight() {
        let frame = IslandGeometry.compactFrame(mode: .floatingPill, screen: screen)
        #expect(frame.height == 34)
    }

    @Test func compactFrameFloatingPillMinWidth() {
        let frame = IslandGeometry.compactFrame(mode: .floatingPill, screen: screen)
        #expect(frame.width >= 150)
    }

    @Test func expandedFrameIsWiderThanCompact() {
        let compact = IslandGeometry.compactFrame(mode: .floatingPill, screen: screen)
        let expanded = IslandGeometry.expandedFrame(mode: .floatingPill, screen: screen)
        #expect(expanded.width > compact.width)
        #expect(expanded.height > compact.height)
    }

    @Test func physicalNotchCompactUsesNotchDimensions() {
        let notchSize = CGSize(width: 200, height: 34)
        let frame = IslandGeometry.compactFrame(mode: .physicalNotch(notchSize: notchSize), screen: screen)
        #expect(frame.width >= notchSize.width)
        #expect(frame.height >= notchSize.height)
    }
}
