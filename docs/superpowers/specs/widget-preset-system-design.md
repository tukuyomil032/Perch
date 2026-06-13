# Perch Widget Preset System — 永続設計記録

## なぜこのファイルが存在するか

この設計はアプリ開発当初から一貫して要求されている仕様だが、
セッションをまたぐと忘れられる傾向がある。このファイルは永続的な
設計根拠として、すべてのセッションで参照すること。

## 核心原則: タブ = プリセット（機能ではない）

### ❌ 間違ったアプローチ（絶対にやらないこと）
- タブ = 機能（Music タブ、AI タブ）
- ExpandedIslandView に「どのウィジェットをどこに配置するか」をハードコード
- 新機能追加 = 新しい IslandPreset case や新しいタブを追加

### ✅ 正しいアプローチ
- タブ = プリセット（「Daily」「Dev」など、ユーザーが名前をつけた設定）
- 各プリセット = WidgetPlacement のリスト（widgetId + size + position）
- 新機能追加 = PerchWidget を実装して WidgetRegistry に register() するだけ
- タブ切り替え = プリセット切り替え（PresetStore.select(id:)）

## ウィジェットとは

Perch の各機能はそれぞれ独立した「ウィジェット」として実装される。

```swift
// perch/Core/WidgetProtocol.swift
protocol PerchWidget: Identifiable {
    var id: String { get }
    var displayName: String { get }
    var icon: String { get }
    var supportedSizes: Set<WidgetSize> { get }
    @MainActor func body(size: WidgetSize) -> AnyView
}
```

## ウィジェットサイズ (WidgetSize)

| サイズ | 典型的な高さ | 用途 |
|--------|------------|------|
| mini | ~20-36px | アイコン + 最小情報 |
| compact | ~44-52px | 1行サマリー |
| standard | ~120-140px | メイン情報パネル |
| full | ~280px | フル機能表示 |

## データモデル

```swift
// perch/Core/WidgetLayout.swift
struct WidgetPlacement: Identifiable, Codable, Sendable {
    var id: UUID
    var widgetId: String    // "nowPlaying" | "aiUsage" | "devStatus" | "fileShelf"
    var size: WidgetSize    // mini | compact | standard | full
    var position: WidgetPosition  // main | sidebar | bottom
}

struct PresetLayout: Identifiable, Codable, Sendable {
    var id: UUID
    var name: String         // ユーザー編集可能
    var widgets: [WidgetPlacement]
}
```

## デフォルトプリセット

**"Daily"**: nowPlaying(standard, main) + aiUsage(compact, sidebar)
**"Dev"**: aiUsage(full, main) + nowPlaying(compact, bottom)

## ExpandedIslandView の正しい実装パターン

```swift
// ✅ 動的レンダリング（正しい）
ForEach(appState.presetStore.activePreset?.widgets ?? []) { placement in
    if let widget = appState.widgetRegistry.widget(forId: placement.widgetId) {
        widget.body(size: placement.size)
    }
}

// ❌ ハードコード（間違い — 絶対にやらない）
switch appState.activePreset {
case .music: NowPlayingView()
case .ai: AIUsageView()
}
```

## 実装状況

| コンポーネント | ファイル | 状態 |
|--------------|---------|------|
| PerchWidget protocol | `perch/Core/WidgetProtocol.swift` | 完成 |
| WidgetSize / WidgetPosition | `perch/Core/WidgetTypes.swift` | 完成 |
| WidgetRegistry | `perch/Core/WidgetRegistry.swift` | 完成 |
| WidgetPlacement / PresetLayout | `perch/Core/WidgetLayout.swift` | 完成 |
| PresetStore (CRUD + 永続化) | `perch/Core/PresetStore.swift` | 完成 |
| NowPlayingWidget (3サイズ) | `perch/UI/Cards/NowPlayingWidget.swift` | PerchWidget 準拠 |
| AIUsageWidget (4サイズ) | `perch/UI/Cards/AIUsageWidget.swift` | PerchWidget 準拠 |
| AppState の移行 | `perch/Core/AppState.swift` | 未完 — まだ IslandPreset を使用 |
| ExpandedIslandView | `perch/UI/ExpandedIslandView.swift` | 未完 — ハードコードレイアウト |
| PresetTabBar | `perch/UI/PresetTabBar.swift` | 未完 — IslandPreset.allCases 使用 |

## Phase 4 拡張予定

- ユーザーによるプリセット追加・削除・リネーム
- プリセット内でウィジェットのドラッグ並び替え
- ウィジェットの有効/無効トグル
- ウィジェットサイズ変更（サポートサイズ内）
