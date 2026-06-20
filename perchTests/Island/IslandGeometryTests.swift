import AppKit
import Testing

@testable import perch

@MainActor
struct IslandGeometryTests {

    // MARK: - Legacy NSScreen-based tests (kept for regression)

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

    // MARK: - ScreenEnvironment-based tests

    // MARK: Compact / floatingPill

    @Test func testCompactFrame_floatingPill_isCentered() {
        let env = ScreenEnvironment.mockNonNotchedMac()
        let frame = IslandGeometry.compactFrame(mode: .floatingPill, environment: env)
        // midX of the pill must equal midX of visibleFrame
        #expect(abs(frame.midX - env.visibleFrame.midX) < 0.5)
    }

    @Test func testCompactFrame_physicalNotch_isCentered() {
        let env = ScreenEnvironment.mockNotchedMacBook()
        let notchSize = env.notchSize
        let mode = IslandMode.physicalNotch(notchSize: notchSize)
        let frame = IslandGeometry.compactFrame(mode: mode, environment: env)
        // physicalNotch uses env.frame (not visibleFrame) for horizontal centering
        #expect(abs(frame.midX - env.frame.midX) < 0.5)
    }

    @Test func testCompactFrame_physicalNotch_isFlushWithTop() {
        let env = ScreenEnvironment.mockNotchedMacBook()
        let notchSize = env.notchSize
        let mode = IslandMode.physicalNotch(notchSize: notchSize)
        let frame = IslandGeometry.compactFrame(mode: mode, environment: env)
        // topOffset for physicalNotch is 0, so frame.maxY == env.frame.maxY
        #expect(abs(frame.maxY - env.frame.maxY) < 0.5)
    }

    @Test func testCompactFrame_floatingPill_hasTopOffset() {
        let env = ScreenEnvironment.mockNonNotchedMac()
        let frame = IslandGeometry.compactFrame(mode: .floatingPill, environment: env)
        // floatingPill topOffset == 20, size.height == 34
        // frame.maxY == visibleFrame.maxY - 20
        let expectedMaxY = env.visibleFrame.maxY - 20
        #expect(abs(frame.maxY - expectedMaxY) < 0.5)
    }

    // MARK: Expanded frame dimensions

    @Test func testExpandedFrame_floatingPill_dimensions() {
        let env = ScreenEnvironment.mockNonNotchedMac()
        let frame = IslandGeometry.expandedFrame(mode: .floatingPill, environment: env)
        #expect(frame.width == 420)
        #expect(frame.height == 280)
    }

    @Test func testExpandedFrame_physicalNotch_dimensions() {
        let env = ScreenEnvironment.mockNotchedMacBook()
        let notchSize = env.notchSize
        let mode = IslandMode.physicalNotch(notchSize: notchSize)
        let frame = IslandGeometry.expandedFrame(mode: mode, environment: env)
        #expect(frame.width == 460)
        #expect(frame.height == 220)
    }

    // MARK: Compact notch width clamp

    @Test func testCompactFrame_notch_widthMatchesNotchOrMinimum() {
        let env = ScreenEnvironment.mockNotchedMacBook()
        let notchSize = env.notchSize  // 208 x 38 for default mock
        let mode = IslandMode.physicalNotch(notchSize: notchSize)
        let frame = IslandGeometry.compactFrame(mode: mode, environment: env)
        let expectedWidth = max(notchSize.width, 150)
        #expect(abs(frame.width - expectedWidth) < 0.5)
    }

    @Test func testCompactFrame_notch_smallNotch_clampsToMinimum() {
        // Simulate a notch narrower than 150pt to verify the clamp
        let tinyNotch = CGSize(width: 100, height: 32)
        let env = ScreenEnvironment.mockNotchedMacBook()
        let frame = IslandGeometry.compactFrame(
            mode: .physicalNotch(notchSize: tinyNotch),
            environment: env
        )
        #expect(frame.width == 150)
    }

    // MARK: Expanded custom height

    @Test func testExpandedFrame_physicalNotch_customHeightRespected() {
        let env = ScreenEnvironment.mockNotchedMacBook()
        let mode = IslandMode.physicalNotch(notchSize: env.notchSize)
        let frame = IslandGeometry.expandedFrame(mode: mode, environment: env, height: 264)
        #expect(frame.width == 460)
        #expect(frame.height == 264)
    }

    @Test func testExpandedFrame_floatingPill_customHeightRespected() {
        let env = ScreenEnvironment.mockNonNotchedMac()
        let frame = IslandGeometry.expandedFrame(mode: .floatingPill, environment: env, height: 360)
        #expect(frame.width == 420)
        #expect(frame.height == 360)
    }

    // MARK: Multi-display / non-zero origin

    @Test func testFrameCalculation_withNonZeroScreenOrigin() {
        // Simulate a secondary display positioned to the left at (-1512, -200)
        let screenFrame = CGRect(x: -1512, y: -200, width: 1512, height: 982)
        let env = ScreenEnvironment.mockNotchedMacBook(frame: screenFrame)
        let notchSize = env.notchSize
        let mode = IslandMode.physicalNotch(notchSize: notchSize)
        let frame = IslandGeometry.compactFrame(mode: mode, environment: env)

        // Must be horizontally centered on this screen (which has midX at -756)
        #expect(abs(frame.midX - env.frame.midX) < 0.5)
        // Must be flush with the top of this screen (frame.maxY == -200 + 982 == 782)
        #expect(abs(frame.maxY - env.frame.maxY) < 0.5)
    }
}
