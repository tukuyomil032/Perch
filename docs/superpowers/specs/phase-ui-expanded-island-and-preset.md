# Phase UI: 展開Island強化 + プリセットカスタマイズ 設計仕様

作成日: 2026-06-14
優先度: Phase 3 完了後（AI Usage Provider 全実装後）に着手

---

## 背景と目標

### なぜこのフェーズが必要か

`docs/superpowers/specs/widget-preset-system-design.md` で定義した「タブ = プリセット（機能ではない）」原則に対し、現在の `ExpandedIslandView` と `PresetTabBar` はウィジェット配置をハードコードしたままになっている。このフェーズで完全移行し、ユーザーがプリセット・ウィジェット構成を Settings 内で自由に編集できるようにする。

### 達成目標

1. `ExpandedIslandView` のハードコードを廃止 → `WidgetRegistry + PresetStore` による動的レンダリング
2. `PresetTabBar` を `presetStore.presets` から動的生成
3. ユーザーが Settings 内でプリセット追加/削除/リネーム・ウィジェット並び替えができる
4. 展開アニメーションを BoringNotch レベルに強化

---

## 軸1: ExpandedIslandView 動的レンダリング移行

### 現状の問題（移行前）

```
perch/UI/ExpandedIslandView.swift  — ウィジェット配置をハードコード
perch/UI/PresetTabBar.swift        — プリセットタブをハードコード
perch/Core/AppState.swift          — IslandPreset enum が残存
```

`ExpandedIslandView` は以下のようなハードコードパターンになっている:
```swift
// ❌ 間違ったパターン（絶対にこの形を継続・増殖させない）
switch appState.activePreset {
case .music:
    NowPlayingWidget()
case .ai:
    AIUsageWidget()
}
```

### 移行後の正しいパターン（widget-preset-system-design.md 準拠）

**ExpandedIslandView（動的レンダリング）:**
```swift
// ✅ これが正しいパターン
ForEach(appState.presetStore.activePreset?.widgets ?? []) { placement in
    if let widget = appState.widgetRegistry.widget(forId: placement.widgetId) {
        AnyView(widget.body(size: placement.size))
    }
}
```

**PresetTabBar（動的生成）:**
```swift
// ✅ これが正しいパターン
ForEach(appState.presetStore.presets) { preset in
    Button(preset.name) {
        appState.presetStore.activate(preset.id)
    }
    .buttonStyle(.tab(isActive: preset.id == appState.presetStore.activePresetId))
}
```

### 移行ファイルと作業内容

| ファイル | 作業内容 |
|---------|---------|
| `perch/UI/ExpandedIslandView.swift` | switch/if ハードコードを `ForEach + WidgetRegistry` に置き換え |
| `perch/UI/PresetTabBar.swift` | 固定タブ定義を `presetStore.presets` iterate に差し替え |
| `perch/Core/AppState.swift` | `IslandPreset` enum を廃止、`PresetStore` に一本化 |

### デフォルトプリセット（移行後も維持）

widget-preset-system-design.md 定義のデフォルト2プリセットは `PresetStore` 初期値として保持:

| プリセット名 | Main | Sidebar/Bottom |
|------------|------|--------------|
| "Daily" | `nowPlaying` (standard) | `aiUsage` (compact, sidebar) |
| "Dev" | `aiUsage` (full) | `nowPlaying` (compact, bottom) |

---

## 軸2: アニメーション強化

### BoringNotch 参照
- GitHub: https://github.com/TheBoredTeam/boring.notch
- 展開アニメーションのモーフィング手法・カード遷移パターンを参照

### 実装目標

| 動作 | 現状 | 目標 |
|-----|------|------|
| 展開時 | `spring(response:0.35, dampingFraction:0.86)` | ウィンドウ拡大とコンテンツ出現を同期 |
| カード切り替え | 瞬時差し替え | `matchedGeometryEffect(id:, in:)` でシームレス遷移 |
| 折りたたみ時 | フェードアウト | コンテンツがピルに「吸い込まれる」縮小 + フェード |

### 使用するアニメーション API

```swift
// カード遷移用 Namespace
@Namespace private var islandNamespace

// ウィジェットコンテンツにマッチ
.matchedGeometryEffect(id: placement.widgetId, in: islandNamespace)

// 折りたたみ時
.scaleEffect(isExpanded ? 1.0 : 0.92)
.opacity(isExpanded ? 1.0 : 0.0)
.animation(.spring(response: 0.32, dampingFraction: 0.88), value: isExpanded)
```

既存のアニメーション定数（`DesignSystem.swift`）を必ず使用:
- `perchSpring`: `.spring(response: 0.32, dampingFraction: 0.82)` — 標準遷移
- `perchExpand`: `.spring(response: 0.35, dampingFraction: 0.86)` — 展開
- `perchSubtle`: `.easeInOut(duration: 0.2)` — 微細変化

---

## 軸3: プリセットカスタマイズUI

### 実装場所

`perch/UI/SettingsView.swift` に「プリセット」タブを新規追加（既存タブを崩さない）

### 機能要件（優先度順）

#### 1. プリセット CRUD

```swift
// 追加
TextField("プリセット名", text: $newPresetName)
    .onSubmit {
        appState.presetStore.addPreset(name: newPresetName)
        newPresetName = ""
    }

// 削除（確認ダイアログあり）
Button("削除", role: .destructive) {
    showDeleteConfirm = true
}
.confirmationDialog("「\(preset.name)」を削除しますか？", isPresented: $showDeleteConfirm) {
    Button("削除", role: .destructive) {
        appState.presetStore.deletePreset(id: preset.id)
    }
}

// リネーム（インライン編集）
TextField(preset.name, text: $editingName)
    .onSubmit { appState.presetStore.renamePreset(id: preset.id, name: editingName) }
```

#### 2. ウィジェット並び替え

```swift
List {
    ForEach(preset.widgets) { placement in
        WidgetRow(placement: placement)
    }
    .onMove { from, to in
        appState.presetStore.reorderWidgets(in: preset.id, from: from, to: to)
    }
}
.environment(\.editMode, .constant(.active))
```

#### 3. ウィジェット追加/削除

```swift
// 追加: 利用可能なウィジェット一覧から選択
ForEach(appState.widgetRegistry.allWidgets.filter { w in
    !preset.widgets.contains(where: { $0.widgetId == w.id })
}) { widget in
    Button("+ \(widget.displayName)") {
        appState.presetStore.addWidget(widget.id, size: .standard, to: preset.id)
    }
}

// 削除
Button(role: .destructive) {
    appState.presetStore.removeWidget(placementId: placement.id, from: preset.id)
}
```

#### 4. ウィジェットサイズ変更

```swift
// widget.supportedSizes に含まれるサイズのみ選択可能
Picker("サイズ", selection: $size) {
    ForEach(Array(widget.supportedSizes).sorted()) { size in
        Text(size.displayName).tag(size)
    }
}
.pickerStyle(.menu)
```

#### 5. 即時プレビュー

`@Observable` のため Settings を開いたまま Island がリアルタイム更新される（追加実装不要）。

### デザイン原則（必須遵守）

- `hallmark` スキル必須適用 — AI生成感のある配色・絵文字・グラデーション背景は禁止
- macOS Settings らしいシンプルな `List` ベース UI
- SF Symbols のみ使用（テキストラベルと組み合わせ）
- `macos-design-guidelines` スキルを実装前に必ず参照

---

## 既存インフラ（変更・削除禁止）

| ファイル | 役割 |
|---------|------|
| `perch/Core/PresetStore.swift` | プリセット CRUD + Defaults 永続化 |
| `perch/Core/WidgetLayout.swift` | `WidgetPlacement`, `PresetLayout` |
| `perch/Core/WidgetRegistry.swift` | ウィジェット登録・検索 |
| `perch/Core/WidgetProtocol.swift` | `PerchWidget` プロトコル |

### PresetStore API（変更禁止・必ず使用）

```swift
// perch/Core/PresetStore.swift
func addPreset(name: String)
func deletePreset(id: String)
func renamePreset(id: String, name: String)
func addWidget(_ widgetId: String, size: WidgetSize, to presetId: String)
func removeWidget(placementId: String, from presetId: String)
func reorderWidgets(in presetId: String, from: IndexSet, to: Int)
func activate(_ presetId: String)

// 参照プロパティ
var presets: [PresetLayout]
var activePreset: PresetLayout?
var activePresetId: String?
```

---

## 実装タスクリスト（フェーズ開始時にチェック）

### Phase UI-1: 動的化（必須・最初に実施）

- [ ] T-UI-1: `ExpandedIslandView.swift` — ハードコード廃止、`ForEach + WidgetRegistry` に移行
- [ ] T-UI-2: `PresetTabBar.swift` — `presetStore.presets` から動的タブ生成
- [ ] T-UI-3: `AppState.swift` — `IslandPreset` enum 廃止、`PresetStore` に一本化
- [ ] T-UI-4: ビルド確認 + 動作確認（Daily / Dev プリセット両方を実機で表示確認）

### Phase UI-2: プリセットカスタマイズUI

- [ ] T-UI-5: `SettingsView.swift` — 「プリセット」タブ追加
- [ ] T-UI-6: プリセット CRUD UI（追加 / 削除 / リネーム）
- [ ] T-UI-7: ウィジェット並び替え UI（`List + .onMove`）
- [ ] T-UI-8: ウィジェット追加 / 削除 UI（WidgetRegistry から選択）
- [ ] T-UI-9: ウィジェットサイズ変更 UI（Picker、supportedSizes フィルタ）
- [ ] T-UI-10: ビルド確認 + 動作確認（Settings から Island がリアルタイム更新）

### Phase UI-3: アニメーション強化

- [ ] T-UI-11: 展開アニメーション強化（`matchedGeometryEffect` + 同期 spring）
- [ ] T-UI-12: 折りたたみ時「吸い込まれる」アニメーション（scale + fade）
- [ ] T-UI-13: 実機確認（MacBook Notch 上で自然な動作を確認）

---

## 使用すべきスキル（フェーズ開始時に必ず確認）

| スキル | タイミング |
|-------|---------|
| `hallmark` | Settings UI 設計時（**必須**） |
| `macos-design-guidelines` | Settings UI パターン確認 |
| `swiftui-pro` | SwiftUI コード品質レビュー |
| `swift-concurrency` | `@MainActor` / `Sendable` 確認 |
| `dynamic-island-ui` | アニメーション実装時 |
| `widget-preset-system` | ExpandedIslandView 移行時（参照必須） |

---

## 既知の制限・注意事項

| 項目 | 内容 |
|------|------|
| ExpandedIslandView の現状 | 実際のハードコードパターンはファイルを読んで確認すること |
| PresetStore API の完全性 | 移行前に `perch/Core/PresetStore.swift` を読み実際の API を確認する |
| `AnyView` のパフォーマンス | ウィジェット数が増えた場合、`AnyView` ラップのオーバーヘッドを計測する |
| プリセット削除時の確認 | 最後のプリセットは削除不可にする（PresetStore 側でガード） |
