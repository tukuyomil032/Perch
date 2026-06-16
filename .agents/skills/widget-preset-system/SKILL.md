# Widget Preset System Skill

## 絶対的ルール

Perch の展開ビューのタブは「プリセット（レイアウト設定）の切り替え」であり、
「機能の切り替え」ではない。

## 新機能を追加するとき

1. `PerchWidget` プロトコルを実装した `nonisolated struct` として機能を実装
2. `AppDelegate.applicationDidFinishLaunching` で `appState.widgetRegistry.register(MyWidget())` を呼ぶ
3. 新しいタブや `IslandPreset` case は **絶対に追加しない**

## ExpandedIslandView のパターン

```swift
// 正しい: 動的レンダリング
ForEach(appState.presetStore.activePreset?.widgets ?? []) { placement in
    if let w = appState.widgetRegistry.widget(forId: placement.widgetId) {
        w.body(size: placement.size)
    }
}

// 絶対にやってはいけない
switch appState.activePreset {
case .music: MusicView()
case .ai: AIView()
}
```

## AppState の正しい状態

```swift
// 正しい
let presetStore = PresetStore()
let widgetRegistry = WidgetRegistry()

// 間違い（削除済み）
var activePreset: IslandPreset = .music
```

## 設計仕様書

`docs/superpowers/specs/widget-preset-system-design.md` を参照。
