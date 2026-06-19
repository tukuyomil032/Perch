// perchTests/Core/WidgetSizeTests.swift
import Testing

@testable import perch

@Suite("WidgetSize")
@MainActor
struct WidgetSizeTests {
    @Test("mini < compact < standard < full")
    func orderingIsCorrect() {
        #expect(WidgetSize.mini < .compact)
        #expect(WidgetSize.compact < .standard)
        #expect(WidgetSize.standard < .full)
    }

    @Test("same size is not less than itself")
    func equalIsNotLess() {
        #expect(!(WidgetSize.standard < .standard))
    }

    @Test("CaseIterable yields 4 cases")
    func allCasesCount() {
        #expect(WidgetSize.allCases.count == 4)
    }

    @Test("rawValue round-trips")
    func rawValueRoundTrip() {
        for size in WidgetSize.allCases {
            #expect(WidgetSize(rawValue: size.rawValue) == size)
        }
    }
}
