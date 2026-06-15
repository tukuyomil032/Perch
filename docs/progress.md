# Perch Development Progress

**Current Phase**: Phase 3 完了 → Phase UI（展開Island強化 + プリセットカスタマイズ）
**Last Updated**: 2026-06-14

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

## Phase 2f-fix: NowPlaying シークバー・歌詞 UI 修正 (2026-06-04)

### 完了タスク

- [x] T0: Apple Music シークバー固まり修正 — `pollAppleMusicPosition` 競合状態 + baseline elapsed=0
- [x] T1: `trackInfo` からアルバム名除去
- [x] T2: 歌詞エリア拡大（スペーサー 24→6pt、`maxHeight` 制約除去）
- [x] T3: 展開アニメーション横移動修正（`NSAnimationContext` 除去、即時 `setFrame`）
- [x] T4: シークバードラッグ操作（`DragGesture` + `manager.seek`）
- [x] T5: twoColumnView 波形・歌詞ボタン spacing 調整

### 修正コミット
- `db65c99` — fix: seek bar frozen due to stale Apple Music position poll
- `46e78ad` — fix: remove album name from track info fallback view
- `9e0df28` — fix: expand lyrics area to fill available card space
- `fc1282c` — fix: eliminate horizontal wobble on expand by removing NSAnimationContext frame animation
- `a21bc4b` — feat: seek bar scrubbing with drag gesture
- `56bfa8d` — fix: adjust waveform and lyrics-button spacing in twoColumnView

### 既知の制限（スコープ外）
- Spotify 広告 UI: Track ID 形式が Spotify バージョンによって異なる可能性。実機テストなしで確認困難
- 次トラックアートワークオーバーレイ: Phase 2g で対応
- YTM 再生コントロール: Phase 2g TypeScript ブリッジで対応

---

## Phase 3: AI Usage (v0.3)

**Last Updated**: 2026-06-14

### 実装済み

- [x] T3-1: AIProvider protocol (`perch/Providers/AIProvider.swift`)
- [x] T3-2: 認証フロー — CLAUDE_CONFIG_DIR env + ~/.claude/projects/ + ~/.config/claude/projects/ フォールバック
- [x] T3-3: Claude Provider (`perch/Providers/Claude/ClaudeProvider.swift`)
  - JSONL パース (ccusage 準拠): composite (messageId:requestId) dedup key
  - isApiErrorMessage フィルタ、ephemeral_1h 2.0x、ephemeral_5m 1.25x
  - CostCalculator.swift: モデル別単価テーブル、cache tiering (5m/1h)
- [x] T3-4: Codex Provider (`perch/Providers/Codex/CodexProvider.swift`)
  - `~/.codex/sessions/YYYY/MM/DD/*.jsonl` を解析（ccusage準拠）
  - `turn_context.model` でモデル名取得、最後の `token_count` イベントを累積トークンとして使用
  - `cached_input_tokens` → cacheReadTokens として CostCalculator に渡す
  - 制限: Codex Desktop（GUI）はJSONL未出力のためトラッキング不可
- [x] T3-5: AIUsageStore + RefreshScheduler (`perch/Features/AIUsage/AIUsageStore.swift`)
- [x] T3-6: AIUsageCard / AIUsageWidget (`perch/Features/AIUsage/`)
- [x] T3-7: Settings UI — Provider切り替えタブ
- [x] T3-8: CompactPillView — AIUsageWidget プロバイダロゴ + コスト表示
- [x] T3-9: IslandWindowController クラッシュ修正 — `observeExpanded()` state-scoped tracking（展開中は `compactWindowWidth` を監視しない）
- [x] T3-10: コスト計算 ccusage 完全準拠修正 (Phase 3.2/3.3)
  - `costUSD` JSONキー修正 (旧: `"cost_usd"` → 正: `"costUSD"`)
  - `isSidechain` フィルタ削除（サブエージェント呼び出しも課金対象）
  - 30日間コスト実測: ccusage Claude分 $528.83 に対して±5%以内
- [x] T3-11: OpenAI Provider (`perch/Providers/OpenAI/OpenAIProvider.swift`)
  - 公式 Usage API (2024年12月発表) — `/v1/organization/costs` + `/v1/organization/usage/completions`
  - **Organization Admin Key 必須**（通常の sk-... 不可）。`platform.openai.com/settings/organization/admin-keys` で発行
  - コスト (USD) + トークン数を30日分・日別・モデル別に取得
  - `amount.value` の String/Double 混在に対応（CodexBar 知見）
- [x] T3-12: OpenRouter Provider (`perch/Providers/OpenRouter/OpenRouterProvider.swift`)
  - Regular Key (`sk-or-v1-...`): `/api/v1/key` で today/weekly/monthly 合計値取得
  - Management Key: `/api/v1/activity` で30日分の日別・モデル別データ取得（チャート表示対応）
  - 両キーを Keychain に個別保存。Management Key があれば自動的にフル機能
- [x] T3-13: Settings UI — OpenAI/OpenRouter API Key 入力フォーム
  - `perch/UI/SettingsView.swift` に "AI Usage" タブを追加
  - SecureField + onSubmit + 削除ボタン
  - `KeychainHelper.swift`: `nonisolated` 追加（Swift 6 で nonisolated context から呼び出し可能に）

### 既知の制限
- Codex/OpenRouter/OpenAI Provider: プロバイダロゴ未実装（Phase 6 対応予定）
- OpenAI Admin Key: Organization 管理者でない個人アカウントでは発行不可の場合あり
- OpenRouter `/api/v1/activity`: 30日上限、約 UTC+30分の集計遅延あり
- Codex Desktop（GUI）セッション: JSONL未出力のため CodexProvider でトラッキング不可
- Gemini / Cursor Provider: Phase 6 以降
- プリセットカスタマイズUI（ウィジェット追加/削除/並び替え）: 次フェーズ（展開UI強化）で実装

---

## Phase 3.5: Visual Polish + NowPlaying Fixes

**Branch**: `phase-3/ai-usage-widget-system`  
**Last Updated**: 2026-06-14

### 目標
16項目の視覚・バグ・機能修正。Dynamic Island黒への統一、アイドルUX改善、衛星サークルのMetal SDF実装、NowPlayingバグ修正、ScreenCaptureKit波形、macOS 26 Liquid Glass対応。

### タスク

#### Group A: CompactPillView / DesignSystem (Claude)
- [x] A1: 背景色を Dynamic Island 黒に統一（.regularMaterial → Color.black）
- [x] A2: アイドル状態UX — "Perch" テキスト削除 + ghost opacity 0.12
- [x] A3: 衛星サークル（デフォルトOFF、右スワイプ、Metal SDF metaball）+ ピルサイズ3段階設定

#### Group B: NowPlaying バグ修正
- [x] B1: YTM アートワーク更新バグ修正（carry-forward guard 除去）
- [x] B2: 波形アニメーション改善（barCount 6→8, maxHeight 14→18, fps 15→60）
- [x] B3: 歌詞ローディングアニメーション（LyricsLoadingView.swift 新規作成）
- [x] B4: 展開音楽カード背景オーディオヴィジュアライザー

#### Group C: 展開ビュー空状態クリーンアップ
- [x] C1: "Not playing" / "No usage data" プレースホルダーテキスト全削除

#### Group D: Codex SVG + i18n
- [x] D1: Codex SVG 白背景除去 + .renderingMode(.original) でグラデーション表示
- [x] D2: i18n 修正 — Settings ラベルを L10n.string() に接続

#### Group E: ScreenCaptureKit
- [x] E1: AudioCaptureService — 8バンド RMS → WaveformView.externalLevels

#### Group F: Liquid Glass (macOS 26)
- [x] F1: GlassEffectContainer — ピル・展開カード・衛星サークルの液体モーフィング

### 既知の制限
- Task F1 (.glassEffect) は macOS 26 Tahoe 以降のみ有効。macOS 14/15 は Metal metaball にフォールバック
- Task E1 ScreenCaptureKit: YTM はブラウザアプリ単位（タブ単位キャプチャはSCK制限により不可）
- Task E1: ScreenCapture権限拒否時は疑似波形にフォールバック

### Phase 3.5 バグ修正タスク（Codexレビュー + ユーザー報告）

- [ ] BF1: AudioCaptureService — vDSP_measqv クラッシュ修正（start >= floatCount guard追加）
- [ ] BF2: MediaRemoteBridge — assumeIsolated → Task { @MainActor in } に変更
- [ ] BF3: YTM stale artwork — fetchAndApplyArtwork 照合条件を track identity のみに限定
- [ ] BF4: ScreenCapture 権限 — 起動時に SCShareableContent アクセスで権限ダイアログ表示
- [ ] BF5: CompactPillView — .contentShape(Capsule()) でタップ/ドラッグヒットエリアを全体に拡張
- [ ] BF6: macOS 26 dualActivityView — providerLogoView を .glassEffect() の外に出してぼかし除去
- [ ] BF7: BackgroundVisualizerView — CSS波 → WaveformView同様の縦バースタイルに変更（24バー、カード全体）

---

## Phase UI: 展開Island強化 + プリセットカスタマイズ（Phase 3 完了後）

詳細仕様: `docs/superpowers/specs/phase-ui-expanded-island-and-preset.md`

### 目標
- `ExpandedIslandView` ハードコードを廃止 → `WidgetRegistry + PresetStore` 動的レンダリングに完全移行
- ユーザーが Settings 内でプリセット追加/削除/リネーム、ウィジェット並び替えができる
- 展開アニメーションを BoringNotch レベルに強化（`matchedGeometryEffect`）

### タスク
- [ ] T-UI-1: `ExpandedIslandView.swift` — ハードコード廃止、`ForEach + WidgetRegistry` に移行
- [ ] T-UI-2: `PresetTabBar.swift` — `presetStore.presets` から動的タブ生成
- [ ] T-UI-3: `AppState.swift` — `IslandPreset` enum 廃止、`PresetStore` に一本化
- [ ] T-UI-4: Settings — プリセット CRUD UI（追加/削除/リネーム）
- [ ] T-UI-5: Settings — ウィジェット並び替え/追加/削除/サイズ変更 UI
- [ ] T-UI-6: 展開アニメーション強化（`matchedGeometryEffect` + spring 同期）

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

### 将来機能: サテライトサークル（将来フェーズで実装予定）

`CompactPillView.isSatelliteVisible` は現在 `false` で固定。
将来、以下のコンテンツを表示するために実装を再開する:
- タイマー（集中モード残り時間表示）
- 集中モード ON/OFF トグル
- **Claude Code / Codex CLI のリアルタイム実行ステータス**（BoringNotch "activity" スタイル）
  - キャラクターアニメーション（ASCII art が動く既存アプリ参考）
  - ツール実行中インジケータ
  - [参考アプリ調査必要: Claude Code status display apps]

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
