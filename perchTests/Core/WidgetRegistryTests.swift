// perchTests/Core/WidgetRegistryTests.swift
import SwiftUI
import Testing

@testable import perch

// テスト用の最小 PerchWidget 実装
private nonisolated struct StubWidget: PerchWidget {
    let id: String
    var displayName: String { id.capitalized }
    var icon: String { "star" }
    var supportedSizes: Set<WidgetSize> { [.compact, .standard] }
    @MainActor func body(size: WidgetSize) -> AnyView { AnyView(EmptyView()) }
}

@Suite("WidgetRegistry")
@MainActor
struct WidgetRegistryTests {
    @Test("register and retrieve widget by id")
    func registerAndRetrieve() {
        let registry = WidgetRegistry()
        registry.register(StubWidget(id: "stub-a"))
        let found = registry.widget(forId: "stub-a")
        #expect(found != nil)
        #expect(found?.id == "stub-a")
    }

    @Test("allWidgets reflects insertion order")
    func insertionOrderPreserved() {
        let registry = WidgetRegistry()
        registry.register(StubWidget(id: "first"))
        registry.register(StubWidget(id: "second"))
        registry.register(StubWidget(id: "third"))
        let ids = registry.allWidgets.map(\.id)
        #expect(ids == ["first", "second", "third"])
    }

    @Test("re-registering same id overwrites without duplicating")
    func reRegisterDoesNotDuplicate() {
        let registry = WidgetRegistry()
        registry.register(StubWidget(id: "dupe"))
        registry.register(StubWidget(id: "dupe"))
        #expect(registry.allWidgets.count == 1)
    }

    @Test("widget(forId:) returns nil for unknown id")
    func unknownIdReturnsNil() {
        let registry = WidgetRegistry()
        #expect(registry.widget(forId: "does-not-exist") == nil)
    }

    @Test("supportedSizes propagated through AnyPerchWidget")
    func supportedSizesPropagated() {
        let registry = WidgetRegistry()
        registry.register(StubWidget(id: "sized"))
        let widget = registry.widget(forId: "sized")
        #expect(widget?.supportedSizes == [.compact, .standard])
    }
}
