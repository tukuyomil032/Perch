import AppKit
import Foundation
import Testing

@testable import perch

// ScreenEnvironment is nonisolated + Sendable, so no @MainActor needed here.
struct NotchDetectorTests {

    // MARK: - Legacy compile-time existence checks

    @Test func isBuiltInDisplayPropertyExists() {
        let screenType = NSScreen.self
        let _ = screenType
    }

    @Test func notchSizePropertyExists() {
        let screenType = NSScreen.self
        let _ = screenType
    }

    @Test func perchPreferredScreenPropertyExists() {
        let screenType = NSScreen.self
        let _ = screenType
    }

    @Test func notchSizeReturnsValidCGSize() {
        let size = CGSize(width: 0, height: 0)
        #expect(size.width >= 0)
        #expect(size.height >= 0)
    }

    // MARK: - ScreenEnvironment.hasNotch

    @Test func testHasNotch_withAuxiliaryAreas_returnsTrue() {
        // mockNotchedMacBook provides auxiliary areas → precise path
        let env = ScreenEnvironment.mockNotchedMacBook()
        #expect(env.hasNotch == true)
    }

    @Test func testHasNotch_withoutAuxiliaryAreas_builtInWithSafeArea_returnsTrue() {
        // Fallback: no auxiliary areas, but isBuiltIn + safeAreaInsetsTop > 0
        let env = ScreenEnvironment(
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 862),
            safeAreaInsetsTop: 38,
            auxiliaryTopLeftArea: nil,
            auxiliaryTopRightArea: nil,
            isBuiltIn: true,
            displayName: "Mock Fallback Notch"
        )
        #expect(env.hasNotch == true)
    }

    @Test func testHasNotch_withoutAuxiliaryAreas_notBuiltIn_returnsFalse() {
        // External monitor: no auxiliary areas, not built-in, even with top inset
        let env = ScreenEnvironment(
            frame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
            visibleFrame: CGRect(x: 0, y: 0, width: 2560, height: 1416),
            safeAreaInsetsTop: 24,
            auxiliaryTopLeftArea: nil,
            auxiliaryTopRightArea: nil,
            isBuiltIn: false,
            displayName: "Mock External Monitor"
        )
        #expect(env.hasNotch == false)
    }

    @Test func testHasNotch_noSafeArea_returnsFalse() {
        let env = ScreenEnvironment.mockNonNotchedMac()
        #expect(env.hasNotch == false)
    }

    // MARK: - ScreenEnvironment.notchSize

    @Test func testNotchSize_precise_calculatesFromAuxiliaryAreas() {
        // Default mockNotchedMacBook: frame.width=1512, left=652, right=652
        // notchWidth = 1512 - 652 - 652 = 208, notchHeight = 38
        let env = ScreenEnvironment.mockNotchedMacBook()
        let size = env.notchSize
        #expect(size.width == 208)
        #expect(size.height == 38)
    }

    @Test func testNotchSize_fallback_returns185Width() {
        // No auxiliary areas, built-in, safeAreaInsetsTop > 0 → width 185
        let env = ScreenEnvironment(
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 862),
            safeAreaInsetsTop: 38,
            auxiliaryTopLeftArea: nil,
            auxiliaryTopRightArea: nil,
            isBuiltIn: true,
            displayName: "Mock Fallback Notch"
        )
        let size = env.notchSize
        #expect(size.width == 185)
        #expect(size.height == 38)
    }

    @Test func testNotchSize_noNotch_returnsZero() {
        let env = ScreenEnvironment.mockNonNotchedMac()
        let size = env.notchSize
        #expect(size == .zero)
    }

    // MARK: - Mock factory defaults

    @Test func testMockNotchedMacBook_hasCorrectDefaults() {
        let env = ScreenEnvironment.mockNotchedMacBook()
        #expect(env.isBuiltIn == true)
        #expect(env.safeAreaInsetsTop == 38)
        #expect(env.auxiliaryTopLeftArea != nil)
        #expect(env.auxiliaryTopRightArea != nil)
        #expect(env.hasNotch == true)
        // Default frame is 1512 x 982
        #expect(env.frame.width == 1512)
        #expect(env.frame.height == 982)
        // visibleFrame height = frame.height - 38
        #expect(env.visibleFrame.height == 944)
    }

    @Test func testMockNonNotchedMac_hasCorrectDefaults() {
        let env = ScreenEnvironment.mockNonNotchedMac()
        #expect(env.isBuiltIn == false)
        #expect(env.safeAreaInsetsTop == 0)
        #expect(env.auxiliaryTopLeftArea == nil)
        #expect(env.auxiliaryTopRightArea == nil)
        #expect(env.hasNotch == false)
        // Default frame is 1440 x 900
        #expect(env.frame.width == 1440)
        #expect(env.frame.height == 900)
        // visibleFrame height = frame.height - 24
        #expect(env.visibleFrame.height == 876)
    }
}
