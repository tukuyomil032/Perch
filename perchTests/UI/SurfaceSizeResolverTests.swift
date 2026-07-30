import Foundation
import Testing

@testable import perch

@Suite("SurfaceSizeResolver")
struct SurfaceSizeResolverTests {
    @Test("a normal screen width uses the base content width")
    func normalScreenUsesBaseWidth() {
        let result = SurfaceSizeResolver.resolve(
            .init(page: .richHome, screenWidth: 1512)
        )
        #expect(result.contentMinWidth == SurfaceMetrics.baseContentWidth)
    }

    @Test("a narrow screen clamps to screenWidth - 60, never below the floor")
    func narrowScreenClampsToScreenInset() {
        let result = SurfaceSizeResolver.resolve(
            .init(page: .richHome, screenWidth: 500)
        )
        #expect(result.contentMinWidth == 440)
    }

    @Test("an extremely narrow screen never drops below maxContentWidthFloor")
    func extremelyNarrowScreenRespectsFloor() {
        let result = SurfaceSizeResolver.resolve(
            .init(page: .richHome, screenWidth: 300)
        )
        #expect(result.contentMinWidth == SurfaceMetrics.maxContentWidthFloor)
    }

    @Test("width never falls below minContentWidth")
    func widthNeverBelowMinimum() {
        let result = SurfaceSizeResolver.resolve(
            .init(page: .richHome, screenWidth: 3000)
        )
        #expect(result.contentMinWidth >= SurfaceMetrics.minContentWidth)
    }

    @Test("richHome height floor matches SurfaceMetrics")
    func richHomeHeightFloor() {
        let result = SurfaceSizeResolver.resolve(
            .init(page: .richHome, screenWidth: 1512)
        )
        #expect(result.contentHeightFloor == SurfaceMetrics.homeContentHeightFloor)
    }
}
