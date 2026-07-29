import Defaults
import Foundation

@MainActor
@Observable
final class PresetStore {
    private(set) var presets: [PresetLayout] = []
    private(set) var activePresetID: UUID?

    var activePreset: PresetLayout? {
        guard let id = activePresetID else { return presets.first }
        return presets.first { $0.id == id }
    }

    init() {
        load()
        if presets.isEmpty {
            injectDefaults()
        }
    }

    func select(id: UUID) {
        guard presets.contains(where: { $0.id == id }) else { return }
        activePresetID = id
        persist()
    }

    func selectNext() {
        guard !presets.isEmpty else { return }
        if let current = activePresetID,
            let index = presets.firstIndex(where: { $0.id == current })
        {
            let next = presets[(index + 1) % presets.count]
            activePresetID = next.id
        } else {
            activePresetID = presets.first?.id
        }
        persist()
    }

    func selectPrevious() {
        guard !presets.isEmpty else { return }
        if let current = activePresetID,
            let index = presets.firstIndex(where: { $0.id == current })
        {
            let prev = (index - 1 + presets.count) % presets.count
            activePresetID = presets[prev].id
        } else {
            activePresetID = presets.last?.id
        }
        persist()
    }

    func add(_ preset: PresetLayout) {
        presets.append(preset)
        persist()
    }

    func update(_ preset: PresetLayout) {
        guard let index = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        presets[index] = preset
        persist()
    }

    func delete(id: UUID) {
        presets.removeAll { $0.id == id }
        if activePresetID == id {
            activePresetID = presets.first?.id
        }
        persist()
    }

    private func load() {
        presets = Defaults[.presets]
        activePresetID = Defaults[.activePresetID]
    }

    private func persist() {
        Defaults[.presets] = presets
        Defaults[.activePresetID] = activePresetID
    }

    private func injectDefaults() {
        let daily = PresetLayout(
            name: "Daily",
            widgets: [
                WidgetPlacement(widgetId: "now-playing", size: .standard, position: .main),
                WidgetPlacement(widgetId: "ai-usage", size: .compact, position: .sidebar),
            ],
            pillPrimary: "now-playing"
        )
        let dev = PresetLayout(
            name: "Dev",
            widgets: [
                WidgetPlacement(widgetId: "ai-usage", size: .full, position: .main),
                WidgetPlacement(widgetId: "now-playing", size: .compact, position: .bottom),
            ],
            pillPrimary: "now-playing"
        )
        presets = [daily, dev]
        activePresetID = daily.id
        persist()
    }
}
