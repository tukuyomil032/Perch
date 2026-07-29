import Foundation
import Testing

@testable import perch

@Suite("WidgetSizeMetrics")
struct WidgetSizeMetricsTests {
    @Test("height(for:) matches the historical AppState/ExpandedIslandView literals")
    func heightsMatchHistoricalValues() {
        #expect(WidgetSizeMetrics.height(for: .mini) == 36)
        #expect(WidgetSizeMetrics.height(for: .compact) == 52)
        #expect(WidgetSizeMetrics.height(for: .standard) == 264)
        #expect(WidgetSizeMetrics.height(for: .full) == 360)
    }

    @Test("height(for:) returns a positive height for every WidgetSize case")
    func heightsArePositiveForAllCases() {
        // height(for:) is now an exhaustive switch, so the compiler already
        // guarantees every WidgetSize case is handled (a missing case is a build
        // failure, not a silent fallback). This test guards the remaining runtime
        // invariant: no case should ever resolve to a zero/negative height.
        for size in WidgetSize.allCases {
            #expect(WidgetSizeMetrics.height(for: size) > 0)
        }
    }
}
