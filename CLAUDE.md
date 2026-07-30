# Perch — macOS Dynamic Island-style Live Hub

## Project Overview

PerchはmacOSの画面上端中央に常駐するDynamic Island風ライブハブアプリ。
MacBookのノッチ周辺に自然に馴染むピル型UIで、AI利用状況、開発ステータス、
Now Playing、ファイル棚などの情報・操作を常時アクセス可能にする。

### References
- [Boring Notch](https://github.com/TheBoredTeam/boring.notch) — Dynamic Island UI、Now Playing
- [NotchDrop](https://github.com/Lakr233/NotchDrop) — 透明ウィンドウ制御、ノッチ検出
- [CodexBar](https://github.com/steipete/CodexBar) — AI使用量監視、Provider分離設計

## Tech Stack

- **Language**: Swift 6, macOS 15 Sequoia+
- **UI**: SwiftUI + AppKit（ウィンドウ制御）
- **Build**: Xcode 16+, .xcodeproj ベース
- **Target**: Apple Silicon / Intel 両対応
- **Bundle ID**: com.tukuyomi032.perch

## Build & Run

```bash
# Xcodeで開く
open perch.xcodeproj

# コマンドラインビルド
xcodebuild -scheme perch -configuration Debug build

# テスト
xcodebuild -scheme perch -configuration Debug test
```

## Architecture

3層構成:

```
UI Layer (SwiftUI)
  ├─ CompactPillView     — ピル型UI
  ├─ ExpandedIslandView  — 展開カード
  ├─ DesignSystem        — 統一デザイントークン
  └─ SettingsView        — 設定画面

Core Layer
  ├─ AppState            — @Observable 全体状態
  ├─ EventBus            — イベント通知
  ├─ Preferences         — Defaults wrapper
  ├─ RefreshScheduler    — actor-based 定期更新
  └─ NotificationService — UNUserNotificationCenter

Integration Layer (AppKit)
  ├─ IslandWindow        — NSWindow 透明オーバーレイ
  ├─ NotchDetector       — ノッチ有無判定
  ├─ IslandGeometry      — frame計算
  └─ MouseEventMonitor   — hover/click検知
```

> **Phase A で Integration Layer 全体を置換予定。**
> `perch/Vendor/NookSurface/`（OpenNook から vendoring、MIT）がウィンドウ・ノッチ形状・
> ジオメトリ・hover を担い、`perch/Island/NookBridge.swift` が AppState との橋渡しだけを持つ。
> 詳細: `docs/opennook-migration-plan.md`

## Module Responsibilities

| Module | Path | Responsibility |
|--------|------|---------------|
| App | `perch/App/` | エントリーポイント、AppDelegate、MenuBar |
| Core | `perch/Core/` | AppState、EventBus、Preferences、RefreshScheduler、NotificationService |
| Island | `perch/Island/` | NSWindow制御、ノッチ検出、ジオメトリ計算、マウスイベント（Phase A 以降は vendored NookSurface のアダプタに縮退） |
| Vendor | `perch/Vendor/` | 外部OSSの取り込み（Phase A で NookSurface を追加）。改変時はファイル冒頭に `// Modified for Perch:` を記す |
| UI | `perch/UI/` | SwiftUIビュー、カード、DesignSystem、設定画面 |
| Features | `perch/Features/` | NowPlaying、FileShelf、AIUsage、DevStatus、HUD |
| Providers | `perch/Providers/` | Claude、Codex、OpenAI、OpenRouter、GitHub |

## Widget Preset System（絶対に忘れてはならない設計原則）

### タブ = プリセット（機能ではない）

Perch のタブは機能スイッチ（Music/AI）ではなく、ユーザー定義の**ウィジェットレイアウト設定**の切り替えである。

### 機能はウィジェットとして実装する

```swift
// 新機能追加時の必須パターン:
nonisolated struct DevStatusWidget: PerchWidget {
    let id = "devStatus"
    let supportedSizes: Set<WidgetSize> = [.compact, .standard]
    func body(size: WidgetSize) -> AnyView { ... }
}
// AppDelegate で登録:
appState.widgetRegistry.register(DevStatusWidget())
```

### 実装済みインフラ（変更・削除禁止）

| ファイル | 役割 |
|---------|------|
| `perch/Core/PresetStore.swift` | プリセット CRUD + Defaults 永続化 |
| `perch/Core/WidgetLayout.swift` | `WidgetPlacement`, `PresetLayout` |
| `perch/Core/WidgetRegistry.swift` | ウィジェット登録・検索 |
| `perch/Core/WidgetProtocol.swift` | `PerchWidget` プロトコル |

詳細: `docs/superpowers/specs/widget-preset-system-design.md`

## Coding Conventions

### Swift Style
- Swift API Design Guidelinesに準拠
- 型名は`UpperCamelCase`、変数・関数は`lowerCamelCase`
- アプリ名は`Perch`（型名の先頭に`Perch`プレフィックス不要。モジュール分離で十分）

### Concurrency
- `@MainActor`: UI関連クラスに必須（AppState、各Store、ViewController）
- `Sendable`: actor境界を越えるデータ型は必ず準拠
- `@Observable`: SwiftUIの状態管理に使用。`ObservableObject`/`@Published`は非推奨
- `actor`: 並列処理が必要なサービス（RefreshScheduler等）

### AppKit + SwiftUI
- Island制御（ウィンドウ、level、Spaces対応）→ AppKit
- 表示コンテンツ（ピル、カード、設定）→ SwiftUI
- `NSHostingController`でSwiftUIをAppKitウィンドウに統合
- AppState は `@Environment` 経由で SwiftUI に注入

### Error Handling
- Swift typed throws を活用
- Provider エラーは `ProviderStatus.error(String)` で保持
- ユーザー向けエラーは `AppState.latestError` に伝播

## Design Rules

### hallmark (Anti-AI-Slop) 準拠
- LLM生成感のあるUIを絶対に避ける
- `.agents/skills/hallmark/` のルールを必ず適用

### Design System (UI/DesignSystem.swift)
- **Grid**: 4pt（hallmark準拠）
- **Corner radius**: pill 17pt、card 28pt（continuous）
- **Typography**: システムフォント（SF Pro / SF Mono）のみ
- **Material**: NSVisualEffectView ultraDark。純粋黒ではなくmacOSらしい半透明vibrancy
- **Animation**:
  - `perchSpring`: `.spring(response: 0.32, dampingFraction: 0.82)` — 標準遷移
  - `perchExpand`: `.spring(response: 0.35, dampingFraction: 0.86)` — 展開
  - `perchSubtle`: `.easeInOut(duration: 0.2)` — 微細変化

### macOS Native Feel
- SF Symbols を一貫して使用
- システムフォント + 適切な weight/size
- macOS HIGに準拠したスペーシング・コントロール
- 背景のvibrancy/blurでmacOSらしい奥行き感

## Skills

### Existing (customized for Perch)
- `swiftui-pro` — SwiftUIコード品質レビュー
- `swift-concurrency` — async/await、actor、Sendable
- `macos-design-guidelines` — macOS HIG実装ガイド
- `hallmark` — Anti-AI-Slop デザイン品質ガードレール

### Project-specific
- `appkit-window-control` — NSWindow/NSPanel、透明ウィンドウ、level（Phase A 以降は vendored NookSurface の改変指針として使う）
- `dynamic-island-ui` — ピルUI、展開アニメーション、カード切り替え
- `ai-provider-integration` — AIProvider protocol、認証、エラーハンドリング

## Dependencies (SPM)

| Package | Version | Purpose | Phase |
|---------|---------|---------|-------|
| ~~KeyboardShortcuts~~ | 2.4.0+ | グローバルショートカット | **Phase A で削除**（Swift 参照ゼロ） |
| Defaults | 9.0.0+ | 型安全な設定保存 | Phase 1 |
| swift-log | 1.12.0+ | ログ基盤 | Phase 1 |
| Sparkle | 2.9.1+ | 自動アップデート | Phase 6 |

### Vendored（SPM ではなくソース取り込み）

| 取り込み元 | ライセンス | 配置 | Phase |
|-----------|-----------|------|-------|
| OpenNook `NookSurface`（19ファイル / 2,617行 / 外部依存ゼロ） | MIT（原著 DynamicNotchKit / Kai Azim、改変 Glendon Chin） | `perch/Vendor/NookSurface/` | A |
| OpenNook `NookScreenLocator` | Apache-2.0 | `perch/Island/ScreenLocator.swift` | A |
| OpenNook Shelf モデル4ファイル（607行） | Apache-2.0 | `perch/Features/FileShelf/` | B |

vendoring した理由: 疑似ノッチ幅（`arbitraryWidth = 300`）が internal 定数で、`screenProvider` /
`configureWindow` / `NookStyle` のいずれからも変更できないため。かつ NookKit の UI 部品
（`NookTopBar` は internal で構造固定、モジュール切替は Menu ポップアップのみ）が Perch の要件に
合わず、どのみち UI を自作するため NookKit を使う実利が小さい。

帰属表示は `NOTICE` と `ThirdPartyLicenses/` に置き、Settings の About / Licenses に表示する。

## Phase Roadmap

| Phase | Version | Scope |
|-------|---------|-------|
| 0 | — | プロジェクト基盤セットアップ |
| 1 | v0.1 | Core Island UI（ピル、ノッチ、展開、Settings、MenuBar） |
| 2 | v0.2 | Now Playing（Spotify、YouTube Music、Apple Music） |
| 3 | v0.3 | AI Usage（Claude、Codex Provider + カード表示） |
| **A** | v0.35 | **Island 層を vendored NookSurface に置換**（デッドコード削除 + macOS 15 引き上げ + 見た目は現行維持） |
| **B** | v0.36 | **Atoll 風展開UI**（モジュールバー、システムステータス、UIMode Rich/Minimal、カレンダー）完了。NowPlaying 再デザインは次のNowPlayingフェーズへ、File ShelfはPhase 4へ、Timerは保留として切り出し済み |
| **C** | v0.37 | **波形の実音キャプチャ修理**（ScreenCaptureKit）+ Audio テスト整備 |
| 4 | v0.4 | 波形を Core Audio Taps へ載せ替え（オレンジ収録インジケータ解消） |
| 5 | v0.5 | Dev Status（GitHub Actions、CI通知） |
| 6 | v1.0 | Sparkle、Homebrew Cask、追加Provider、輝度HUD、安定化 |

Phase A/B/C の詳細・判断背景・検証済み事実は
`docs/opennook-migration-plan.md` を参照。

## progress.md 運用ルール

`docs/progress.md` は各フェーズのタスクチェックリストの正本。以下を厳守する:

- 各フェーズ開始前に、`docs/progress.md` に該当フェーズのタスクチェックリストが無ければ
  作業着手前に追加する。
- 1タスク実装 → 1コミットの直後に、`docs/progress.md` の該当チェックボックスを更新する。
  まとめて後回しにせず、次のタスクに進む前に必ず更新する。
- 実装中にユーザーから「ついでにこれもやって」的な追加依頼が来た場合、その場で黙って
  今のタスクに組み込まない。まず `docs/progress.md` に新規タスクとして明示的に追記して
  から着手する（追加理由・元タスクとの関係を一言添える）。これにより後から
  「本筋からズレた」かどうかを追跡できるようにする。
- 当初のタスク定義から仕様を変更する場合（技術的制約で断念、方針転換など）も、チェックを
  付けるだけでなく変更内容と理由を該当タスクの下に一言残す。
- フェーズ完了時は該当フェーズ節の `Last Updated` を更新し、次フェーズの見出しを追加する。

## Distribution

- GitHub Releases
- Homebrew Cask: `tukuyomil032/homebrew-tap`
- Sparkle 自動アップデート
- App Storeは対象外（window level制御、private API使用のため）

## Notifications

重要イベント（CI failure、AI使用量警告等）はmacOS通知センターに送信。
- 通知音: macOSデフォルト or ユーザー指定MP3（Settings画面で選択）
- UNUserNotificationCenter 使用
