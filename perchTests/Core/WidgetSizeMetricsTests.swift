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

    @Test("heights dictionary covers every WidgetSize case")
    func heightsCoverAllCases() {
        for size in WidgetSize.allCases {
            #expect(WidgetSizeMetrics.heights[size] != nil)
        }
    }
}
