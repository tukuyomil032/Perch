import Foundation
// perchTests/Core/WidgetLayoutTests.swift
import Testing

@testable import perch

@Suite("WidgetLayout Codable")
@MainActor
struct WidgetLayoutTests {
    @Test("WidgetPlacement encodes and decodes")
    func widgetPlacementRoundTrip() throws {
        let placement = WidgetPlacement(
            widgetId: "now-playing", size: .standard, position: .main)
        let data = try JSONEncoder().encode(placement)
        let decoded = try JSONDecoder().decode(WidgetPlacement.self, from: data)
        #expect(decoded.id == placement.id)
        #expect(decoded.widgetId == "now-playing")
        #expect(decoded.size == .standard)
        #expect(decoded.position == .main)
    }

    @Test("WidgetPlacement sidebar position survives round-trip")
    func widgetPlacementSidebar() throws {
        let placement = WidgetPlacement(widgetId: "ai-usage", size: .compact, position: .sidebar)
        let data = try JSONEncoder().encode(placement)
        let decoded = try JSONDecoder().decode(WidgetPlacement.self, from: data)
        #expect(decoded.position == .sidebar)
        #expect(decoded.size == .compact)
    }

    @Test("PresetLayout with widgets round-trips")
    func presetLayoutRoundTrip() throws {
        let p1 = WidgetPlacement(widgetId: "now-playing", size: .standard, position: .main)
        let p2 = WidgetPlacement(widgetId: "ai-usage", size: .compact, position: .sidebar)
        let preset = PresetLayout(name: "TestPreset", widgets: [p1, p2])
        let data = try JSONEncoder().encode(preset)
        let decoded = try JSONDecoder().decode(PresetLayout.self, from: data)
        #expect(decoded.name == "TestPreset")
        #expect(decoded.widgets.count == 2)
        #expect(decoded.widgets[0].widgetId == "now-playing")
        #expect(decoded.widgets[1].widgetId == "ai-usage")
    }

    @Test("PresetLayout with nil pill fields round-trips")
    func presetLayoutNilPillFields() throws {
        let preset = PresetLayout(name: "NoPills", widgets: [])
        let data = try JSONEncoder().encode(preset)
        let decoded = try JSONDecoder().decode(PresetLayout.self, from: data)
        #expect(decoded.pillPrimary == nil)
        #expect(decoded.pillSecondary == nil)
    }

    @Test("PresetLayout with optional pill strings survives round-trip")
    func presetLayoutWithPills() throws {
        let preset = PresetLayout(
            name: "WithPills", widgets: [],
            pillPrimary: "now-playing", pillSecondary: "ai-usage")
        let data = try JSONEncoder().encode(preset)
        let decoded = try JSONDecoder().decode(PresetLayout.self, from: data)
        #expect(decoded.pillPrimary == "now-playing")
        #expect(decoded.pillSecondary == "ai-usage")
    }
}
