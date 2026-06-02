# Perch Development Progress

**Current Phase**: Phase 0 — Project Setup
**Last Updated**: 2026-06-02

---

## Phase 0: Project Setup

- [x] T0-1: デザインリファレンス収集（docs/design-references.md, docs/img/）
- [x] T0-2: Xcodeプロジェクト再編（App/Core/Island/UI/Features/Providers構造）
- [x] T0-3: .gitignore整備
- [ ] T0-4: SPM依存ライブラリ追加（KeyboardShortcuts, Defaults, swift-log）— Phase 1開始時にXcodeから追加
- [x] T0-5: Info.plist / Entitlements設定（LSUIElement, network.client）
- [x] T0-6: CLAUDE.md作成（プロジェクトレベル、包括的）
- [x] T0-7: AGENTS.md作成（CLAUDE.mdへのシンボリックリンク）
- [x] T0-8: progress.md作成
- [ ] T0-9: 既存スキルのPerch向けカスタマイズ（swiftui-pro, swift-concurrency, macos-design-guidelines）
- [ ] T0-10: 新規スキル作成（appkit-window-control, dynamic-island-ui, ai-provider-integration）
- [ ] T0-11: spec doc作成（docs/superpowers/specs/）

---

## Phase 1: Core Island UI (v0.1)

- [ ] T1-1: AppDelegate + アプリライフサイクル
- [ ] T1-2: IslandWindow（NSWindow透明オーバーレイ）
- [ ] T1-3: NotchDetector（ノッチ有無判定）
- [ ] T1-4: IslandGeometry + IslandConfiguration
- [ ] T1-5: IslandWindowController（SwiftUI hosting）
- [ ] T1-6: CompactPillView（ピル型UI + vibrancy）
- [ ] T1-7: ExpandedIslandView（展開カード）
- [ ] T1-8: RootIslandView（compact↔expandedモーフィング）
- [ ] T1-9: AppState（@Observable状態管理）
- [ ] T1-10: MouseEventMonitor（hover/click検知）
- [ ] T1-11: MenuBarController（NSStatusItem）
- [ ] T1-12: Settings画面（SwiftUI Settings scene）
- [ ] T1-13: Login at launch（ServiceManagement）

---

## Phase 2: Now Playing (v0.2)

- [ ] T2-1: NowPlayingManager（MRMediaRemote dynamic loading）
- [ ] T2-2: NowPlayingState（データモデル）
- [ ] T2-3: NowPlayingCard（展開 + compact表示）
- [ ] T2-4: アニメーション演出（bounce, crossfade, 波形）
- [ ] T2-5: 再生コントロール（play/pause/next/prev）

---

## Phase 3: AI Usage (v0.3)

- [ ] T3-1: AIProvider protocol
- [ ] T3-2: 認証フロー（Keychain, CLI config, env）
- [ ] T3-3: Claude Provider
- [ ] T3-4: Codex Provider
- [ ] T3-5: AIUsageStore + RefreshScheduler
- [ ] T3-6: AIUsageCard
- [ ] T3-7: Settings UI（Provider設定）

---

## Phase 4: File Shelf (v0.4)

- [ ] T4-1: ドラッグ&ドロップ（NSDraggingDestination）
- [ ] T4-2: ShelfItem + ShelfStore
- [ ] T4-3: TemporaryFileStorage
- [ ] T4-4: 自動削除ポリシー
- [ ] T4-5: FileShelfCard
- [ ] T4-6: Quick Look（QLPreviewPanel）
- [ ] T4-7: AirDrop（NSSharingService）

---

## Phase 5: Dev Status (v0.5)

- [ ] T5-1: GitHubClient（REST API v3）
- [ ] T5-2: GitHubActionsProvider
- [ ] T5-3: LocalGitProvider（オプション）
- [ ] T5-4: ProcessWatcher（Claude Code / Codex CLI状態）
- [ ] T5-5: DevStatusCard
- [ ] T5-6: ピル通知 + macOS通知センター連携

---

## Phase 6: Stabilization & Distribution (v1.0)

- [ ] T6-1: NotificationService（UNNotificationCenter + カスタムMP3）
- [ ] T6-2: デザインシステム最終整備
- [ ] T6-3: Sparkle統合（自動アップデート）
- [ ] T6-4: Homebrew Cask（tukuyomil032/homebrew-tap）
- [ ] T6-5: 追加Provider（OpenAI, OpenRouter）
- [ ] T6-6: HUD（バッテリー、音量表示）
- [ ] T6-7: README / Docs整備
- [ ] T6-8: パフォーマンス最適化
