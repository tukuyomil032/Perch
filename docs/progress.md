# Perch Development Progress

**Current Phase**: Phase 2e 完了 → Phase 3 へ
**Last Updated**: 2026-06-04

---

## Phase 0: Project Setup

- [x] T0-1: デザインリファレンス収集（docs/design-references.md, docs/img/）
- [x] T0-2: Xcodeプロジェクト再編（App/Core/Island/UI/Features/Providers構造）
- [x] T0-3: .gitignore整備
- [x] T0-4: SPM依存ライブラリ追加（KeyboardShortcuts, Defaults, swift-log）— Phase 1開始時にXcodeから追加
- [x] T0-5: Info.plist / Entitlements設定（LSUIElement, network.client）
- [x] T0-6: CLAUDE.md作成（プロジェクトレベル、包括的）
- [x] T0-7: AGENTS.md作成（CLAUDE.mdへのシンボリックリンク）
- [x] T0-8: progress.md作成
- [x] T0-9: 既存スキルのPerch向けカスタマイズ（swiftui-pro, swift-concurrency, macos-design-guidelines）
- [x] T0-10: 新規スキル作成（appkit-window-control, dynamic-island-ui, ai-provider-integration）
- [x] T0-11: spec doc作成（docs/superpowers/specs/）

---

## Phase 1: Core Island UI (v0.1)

- [x] T1-1: AppDelegate + アプリライフサイクル
- [x] T1-2: IslandWindow（NSWindow透明オーバーレイ）
- [x] T1-3: NotchDetector（ノッチ有無判定）
- [x] T1-4: IslandGeometry + IslandMode（floatingPill / physicalNotch）
- [x] T1-5: IslandWindowController（SwiftUI hosting + withObservationTracking）
- [x] T1-6: CompactPillView（ピル型UI + vibrancy + hover）
- [x] T1-7: ExpandedIslandView（展開カード）
- [x] T1-8: RootIslandView（compact↔expandedモーフィング）
- [x] T1-9: AppState（@Observable状態管理 + expand/collapse + swift-log）
- [x] T1-10: MouseEventMonitor（hover/click検知 + autoCollapseDelay）
- [x] T1-11: MenuBarController（NSStatusItem + bird icon）
- [x] T1-12: Settings画面（SwiftUI Settings scene + Defaults integration）
- [x] T1-13: Login at launch（SMAppService + LoginItemManager）

---

## Phase 2: Now Playing (v0.2)

- [x] T2-1: NowPlayingManager（DistributedNotificationCenter + AppleScript polling）
- [x] T2-2: NowPlayingState（データモデル）
- [x] T2-3: NowPlayingCard（展開 + compact表示）
- [x] T2-4: アニメーション演出（bounce, crossfade, 波形）
- [x] T2-5: 再生コントロール（play/pause/next/prev）
- [x] Migration: MRMediaRemote → DistributedNotificationCenter（2026-06-03）
  - macOS 16 blocks MRMediaRemote with Code=3 Operation not permitted
  - Adopted multi-source detection: Spotify, Apple Music, YouTube Music (via Chrome)
  - Fallback to MRMediaRemote for macOS < 15.4

---

## Phase 2c: Now Playing 品質向上・UI大改修 (2026-06-03)

### 完了タスク (T1〜T10)
- [x] T1: IslandGeometry screen.visibleFrame 修正 / Settings statusWindow+2 昇格
- [x] T2: YouTube Music — Chromium 9ブラウザ動的検出 (NSWorkspace.runningApplications)
- [x] T3: NowPlayingState — MusicSource enum, liveRemaining, elapsed clamp, enriched(artwork:)
- [x] T4: ArtworkFetcher actor 新規作成 (Spotify URL fetch / Apple Music binary descriptor)
- [x] T5: NowPlayingManager — アートワーク取得 + Apple Music position ポーリング(1.5s)統合
- [x] T6: WaveformView 6バー sin波 TimelineView 全面書き換え
- [x] T7: NowPlayingCompact UI修正 (alignment .center / marquee 25px/s / source badge)
- [x] T8: NowPlayingCard iOS Dynamic Island スタイル大改修
- [x] T9: i18n (L10n.swift / en.lproj / ja.lproj / Settings NowPlayingTab + LanguageTab)
- [x] T10: CodeRabbit 指摘解消 (empty state 言語統一)

### 新規ファイル
- `perch/Features/NowPlaying/ArtworkFetcher.swift`
- `perch/Core/L10n.swift`
- `perch/Resources/en.lproj/Localizable.strings`
- `perch/Resources/ja.lproj/Localizable.strings`

### 既知バグ（Phase 2c-fix で対応済み ✅）
- [x] CI ビルド/テスト失敗 → swift-format 自動修正でクリア（commit `4ef8cf5`）
- [x] YTM active tab のみ検索 → 全タブスキャンに変更（commit `e57ca77`）
- [x] Settings ウィンドウ非表示 → activate 順序修正 + makeKeyAndOrderFront（commit `367ad83`）
- [x] ピル背景色がグレー → VibrancyBackground に .darkAqua 強制（commit `570e427`）
- [x] 展開カード高さ不足 → 180pt → 280pt（commit `9a382f7`）
- [x] YTM アートワーク未取得 → iTunes Search API 実装（commit `5d60a59`）
- [x] MRMediaRemote.sendCommand 誤送信 → Spotify/Apple Music は AppleScript 直送（commit `9f23bcb`）
- [x] コンパクトピル タイトル縦位置ずれ → MarqueeText に maxHeight: 16 追加（commit `31686da`）

---

## Phase 2c-fix (2026-06-03)

8件の既知バグをすべて修正。CI グリーン維持。

### 修正内容
- **CI**: swift-format lint 自動修正（import ソート・guard 改行）
- **UI**: 展開カード高さ 280pt、ピル near-black 背景、タイトル縦中央
- **YTM**: バックグラウンドタブ検出 + iTunes API アートワーク取得
- **Settings**: activate → sendAction 順に変更、makeKeyAndOrderFront 追加
- **再生コントロール**: Spotify/Apple Music は AppleScript 直送（MRMediaRemote 誤送信を排除）

### 既知の制限（将来の改善候補）
- YTM アートワーク: iTunes API の `&` を含むアーティスト名でクエリが分断される可能性
- YTM 再生コントロール: MRMediaRemote fallback のまま（browser AppleScript 制御は未実装）

---

## Phase 2d: NowPlaying Stability & UX Polish (2026-06-04)

### 完了タスク

- [x] T1: YTM title/artist 逆転修正 (`fromYouTubeMusicTitle` parts[0]=title に修正)
- [x] T1: `thumbnailURL: URL?` を NowPlayingState に追加 + `init?(fromYouTubeMusicJS:)` 新規
- [x] T1: Equatable に `thumbnailURL` を追加（サムネイル専用更新の取りこぼし防止）
- [x] T2: ソース優先度システム — MRMediaRemote(1) < YTM(2) < Spotify/AM(3)
- [x] T3: YTM JS injection (`pollYouTubeMusicJS`) — DOM から title/artist/thumbnail/playing を直接取得
- [x] T3: ArtworkFetcher — thumbnailURL 直接取得 + iTunes API ベストマッチ改善
- [x] T4: アートワーク carry-forward — 曲切替時に旧アートワークを維持してフラッシュ防止
- [x] T5: コンパクトピル "title — artist" フォーマット（ソースバッジ削除）
- [x] T6: マーキーテキスト async ループ化（5 秒ポーズ + race condition 修正）
- [x] T7: 波形カラーテーマ — `NSImage+DominantColor` (CIAreaAverage + 彩度ブースト)
- [x] T7: CIContext キャッシュ（static let）でパフォーマンス最適化
- [x] T8: ソース設定トグル — Spotify / Apple Music / YouTube Music 個別有効化
- [x] T9: IslandWindow `tabbingMode = .disallowed` — 起動時の "Cannot index window tabs" 警告除去

### 新規ファイル
- `perch/Core/NSImage+DominantColor.swift`

### 既知の制限（将来の改善候補）
- YTM JS injection: YTM DOM 構造が変わると CSS セレクタが壊れる可能性（タブタイトル解析にフォールバック）
- YTM 再生コントロール: MRMediaRemote fallback のまま（AppleScript ブラウザ制御は未実装）
- YTM タブ閉じ時: currentState がクリアされない（次のポーリングまで残留）
- ソース無効化時: アクティブな再生状態がすぐにクリアされない（次の更新まで残留）
- `init?(fromYouTubeMusicJS:)`: ユニットテスト未実装

---

## Phase 2e: NowPlaying UX Fix (2026-06-04)

### 完了タスク

- [x] T1: MarqueeText — スクロール完了後にセンターでフェードイン復帰（5秒ブランク→フェードイン0.4s+5秒静止に修正）
- [x] T2: アートワーク自動更新 — `artworkID: UUID?` 追加、`enriched()` で新 UUID 生成、Equatable に組み込み
- [x] T2: NowPlayingManager carry-forward / `pollAppleMusicPosition` で `artworkID` 引き継ぎ
- [x] T3: Settings ログ — `canBecomeKey` フィルタ追加（NSStatusBarWindow の誤 `makeKeyAndOrderFront` を防止）
- [x] T4: 展開・収納アニメーション改善 — `dampingFraction: 0.65→0.88`、`scale: 0.92→0.96`、NSAnimationContext `duration: 0.28→0.30` 同期

### 修正コミット
- `0faf2f9` — fix: marquee text fades in at center instead of appearing blank for 5 seconds
- `b0dd699` — fix: artwork updates now trigger SwiftUI re-render via artworkID
- `1b378cb` — fix: filter canBecomeKey in openSettings to skip NSStatusBarWindow
- `687a484` — fix: smoother expand/collapse animation, remove left-right wobble

---

## Phase 2f: NowPlaying Polish (2026-06-04)

### 完了タスク

- [x] T0: Settings ウィンドウ — `openSettings` 環境値ブリッジ（macOS 14+ 対応）
- [x] T1: YTM タイトル — `" | YouTube Music"` / `" – YouTube Music"` suffix 除去
- [x] T2: アートワーク切り替えアニメーション（ピル: scale+fade / カード: Y軸 3D flip）
- [x] T3: Spotify 広告検出 — `isAd: Bool` フラグ + megaphone プレースホルダー
- [x] T4: 波形グラデーション — `LinearGradient` (bottom 50% → top 100%)
- [x] T5: 展開・収納アニメーション — `matchedGeometryEffect` 除去 + asymmetric spring
- [x] T6: 歌詞表示 — LRCLIB 行レベル sync + 2カラム(Pattern 1)/フルビュー(Pattern 2)切替
- [x] T7: docs 更新 + pre-Phase-3 スペック作成

### 新規ファイル
- `perch/Features/NowPlaying/LyricsStore.swift` — actor, LRCLIB fetch, LRC parse
- `perch/Features/NowPlaying/LyricsView.swift` — ScrollViewReader, opacity, mask

### 既知の制限
- 歌詞 word-level ハイライト: MusicKit TTML entitlement が必要なため本プロジェクトでは実装しない（行レベルで確定）
- Spotify 広告アートワーク: DistributedNotificationCenter に広告サムネ URL なし（megaphone のみ）
- YTM 再生コントロール: Phase 2g で TypeScript ブリッジとして実装予定

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
