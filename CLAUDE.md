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

- **Language**: Swift 6, macOS 14 Sonoma+
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

## Module Responsibilities

| Module | Path | Responsibility |
|--------|------|---------------|
| App | `perch/App/` | エントリーポイント、AppDelegate、MenuBar |
| Core | `perch/Core/` | AppState、EventBus、Preferences、RefreshScheduler、NotificationService |
| Island | `perch/Island/` | NSWindow制御、ノッチ検出、ジオメトリ計算、マウスイベント |
| UI | `perch/UI/` | SwiftUIビュー、カード、DesignSystem、設定画面 |
| Features | `perch/Features/` | NowPlaying、FileShelf、AIUsage、DevStatus、HUD |
| Providers | `perch/Providers/` | Claude、Codex、OpenAI、OpenRouter、GitHub |

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

### Project-specific (to be created)
- `appkit-window-control` — NSWindow/NSPanel、透明ウィンドウ、level
- `dynamic-island-ui` — ピルUI、展開アニメーション、カード切り替え
- `ai-provider-integration` — AIProvider protocol、認証、エラーハンドリング

## Dependencies (SPM)

| Package | Version | Purpose | Phase |
|---------|---------|---------|-------|
| KeyboardShortcuts | 2.4.0+ | グローバルショートカット | Phase 1 |
| Defaults | 9.0.0+ | 型安全な設定保存 | Phase 1 |
| swift-log | 1.12.0+ | ログ基盤 | Phase 1 |
| Sparkle | 2.9.1+ | 自動アップデート | Phase 6 |

## Phase Roadmap

| Phase | Version | Scope |
|-------|---------|-------|
| 0 | — | プロジェクト基盤セットアップ |
| 1 | v0.1 | Core Island UI（ピル、ノッチ、展開、Settings、MenuBar） |
| 2 | v0.2 | Now Playing（Spotify、YouTube Music、Apple Music） |
| 3 | v0.3 | AI Usage（Claude、Codex Provider + カード表示） |
| 4 | v0.4 | File Shelf（D&D、一時保存、Quick Look、AirDrop） |
| 5 | v0.5 | Dev Status（GitHub Actions、CI通知） |
| 6 | v1.0 | Sparkle、Homebrew Cask、追加Provider、HUD、安定化 |

## Distribution

- GitHub Releases
- Homebrew Cask: `tukuyomil032/homebrew-tap`
- Sparkle 自動アップデート
- App Storeは対象外（window level制御、private API使用のため）

## Notifications

重要イベント（CI failure、AI使用量警告等）はmacOS通知センターに送信。
- 通知音: macOSデフォルト or ユーザー指定MP3（Settings画面で選択）
- UNUserNotificationCenter 使用
