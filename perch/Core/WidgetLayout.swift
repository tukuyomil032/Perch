import Defaults
import Foundation

// WidgetPlacement and PresetLayout are pure Sendable data models.
// They live in a separate file without any @MainActor context so that
// the compiler does not infer @MainActor on their synthesised Decodable
// init(from:) — which would cause Defaults.Serializable conformances to
// cross actor boundaries under Swift 6 strict concurrency.

struct WidgetPlacement: Identifiable, Sendable {
    var id: UUID
    var widgetId: String
    var size: WidgetSize
    var position: WidgetPosition

    init(id: UUID = UUID(), widgetId: String, size: WidgetSize, position: WidgetPosition) {
        self.id = id
        self.widgetId = widgetId
        self.size = size
        self.position = position
    }
}

extension WidgetPlacement: Codable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        widgetId = try container.decode(String.self, forKey: .widgetId)
        size = try container.decode(WidgetSize.self, forKey: .size)
        position = try container.decode(WidgetPosition.self, forKey: .position)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(widgetId, forKey: .widgetId)
        try container.encode(size, forKey: .size)
        try container.encode(position, forKey: .position)
    }

    private enum CodingKeys: String, CodingKey {
        case id, widgetId, size, position
    }
}

struct PresetLayout: Identifiable, Sendable {
    var id: UUID
    var name: String
    var widgets: [WidgetPlacement]
    var pillPrimary: String?
    var pillSecondary: String?

    init(
        id: UUID = UUID(),
        name: String,
        widgets: [WidgetPlacement] = [],
        pillPrimary: String? = nil,
        pillSecondary: String? = nil
    ) {
        self.id = id
        self.name = name
        self.widgets = widgets
        self.pillPrimary = pillPrimary
        self.pillSecondary = pillSecondary
    }
}

extension PresetLayout: Codable {
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        widgets = try container.decode([WidgetPlacement].self, forKey: .widgets)
        pillPrimary = try container.decodeIfPresent(String.self, forKey: .pillPrimary)
        pillSecondary = try container.decodeIfPresent(String.self, forKey: .pillSecondary)
    }

    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(widgets, forKey: .widgets)
        try container.encodeIfPresent(pillPrimary, forKey: .pillPrimary)
        try container.encodeIfPresent(pillSecondary, forKey: .pillSecondary)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, widgets, pillPrimary, pillSecondary
    }
}

extension WidgetSize: Defaults.Serializable {}
extension WidgetPosition: Defaults.Serializable {}
extension WidgetPlacement: Defaults.Serializable {}
extension PresetLayout: Defaults.Serializable {}

extension Defaults.Keys {
    static let presets = Key<[PresetLayout]>("presets", default: [])
    static let activePresetID = Key<UUID?>("activePresetID", default: nil)
}
