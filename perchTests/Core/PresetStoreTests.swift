// perchTests/Core/PresetStoreTests.swift
import Foundation
import Testing

@testable import perch

@Suite("PresetStore", .serialized)
@MainActor
struct PresetStoreTests {
    // 各テストインスタンス生成時に UserDefaults をリセット → PresetStore.init() が
    // injectDefaults() を呼び Daily+Dev の2プリセットが生成された状態から開始する
    init() {
        UserDefaults.standard.removeObject(forKey: "presets")
        UserDefaults.standard.removeObject(forKey: "activePresetID")
    }

    @Test("init injects Daily and Dev presets when empty")
    func initInjectsDefaults() {
        let store = PresetStore()
        #expect(store.presets.count == 2)
        #expect(store.presets[0].name == "Daily")
        #expect(store.presets[1].name == "Dev")
    }

    @Test("activePreset defaults to first preset")
    func activePresetIsFirstByDefault() {
        let store = PresetStore()
        #expect(store.activePreset?.name == "Daily")
    }

    @Test("default Daily and Dev presets both name now-playing as pillPrimary")
    func defaultPresetsSetPillPrimary() {
        let store = PresetStore()
        #expect(store.presets[0].pillPrimary == "now-playing")
        #expect(store.presets[1].pillPrimary == "now-playing")
    }

    @Test("selectNext moves to Dev from Daily")
    func selectNextAdvances() {
        let store = PresetStore()
        store.selectNext()
        #expect(store.activePreset?.name == "Dev")
    }

    @Test("selectNext wraps from last to first")
    func selectNextWraps() {
        let store = PresetStore()
        store.selectNext()  // Daily → Dev
        store.selectNext()  // Dev → Daily (wrap)
        #expect(store.activePreset?.name == "Daily")
    }

    @Test("selectPrevious wraps from first to last")
    func selectPreviousWraps() {
        let store = PresetStore()
        // Active is Daily (index 0), going back wraps to Dev (last)
        store.selectPrevious()
        #expect(store.activePreset?.name == "Dev")
    }

    @Test("add inserts a new preset")
    func addInsertsPreset() {
        let store = PresetStore()
        let new = PresetLayout(name: "Custom")
        store.add(new)
        #expect(store.presets.count == 3)
        #expect(store.presets.last?.name == "Custom")
    }

    @Test("update modifies existing preset name")
    func updateModifiesPreset() {
        let store = PresetStore()
        var modified = store.presets[0]
        modified.name = "Renamed"
        store.update(modified)
        #expect(store.presets[0].name == "Renamed")
    }

    @Test("delete removes preset and falls back to first remaining")
    func deleteRemovesPreset() {
        let store = PresetStore()
        let dailyId = store.presets[0].id
        store.delete(id: dailyId)
        #expect(store.presets.count == 1)
        #expect(store.presets[0].name == "Dev")
        #expect(store.activePreset?.name == "Dev")
    }

    @Test("select(id:) with unknown id is a no-op")
    func selectUnknownIdNoOp() {
        let store = PresetStore()
        let before = store.activePresetID
        store.select(id: UUID())
        #expect(store.activePresetID == before)
    }
}
