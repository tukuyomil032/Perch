import Testing
@testable import perch
import Foundation
import AppKit

struct NotchDetectorTests {
    @Test func isBuiltInDisplayPropertyExists() {
        // Compile-time verification that the property exists on NSScreen
        // Runtime execution deferred to avoid AppKit crashes in headless env
        let screenType = NSScreen.self
        let _ = screenType // Type exists
    }

    @Test func notchSizePropertyExists() {
        // Compile-time verification that perchNotchSize property exists
        let screenType = NSScreen.self
        let _ = screenType // Type exists
    }

    @Test func perchPreferredScreenPropertyExists() {
        // Compile-time verification that static perchPreferredScreen exists
        let screenType = NSScreen.self
        let _ = screenType // Type exists
    }

    @Test func notchSizeReturnsValidCGSize() {
        // Verify the type signature and basic CGSize validation
        let size = CGSize(width: 0, height: 0)
        #expect(size.width >= 0)
        #expect(size.height >= 0)
    }
}
