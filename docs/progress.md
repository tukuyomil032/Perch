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

> Phase B の B6（File Shelf モジュール）はこのフェーズと完全に重複していたため、
> Phase B のスコープから削除しここに一本化した（2026-07-30）。

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

---

## Phase A / B / C: OpenNook 移行 + Atoll 風 UI + 波形修理

**Branch**: Phase A `feat/island-opennook-vendored` / Phase B `feat/expanded-ui-redesign`
**Last Updated**: 2026-07-30（Phase B 完了）
**設計書**: `docs/opennook-migration-plan.md`（判断背景・制約・検証済み事実の全文）

### 目標

Island 層の独自実装（`perch/Island/` 595行）を vendored NookSurface に置き換え、展開UIを
作り直し、実音波形を実際に動かす。機能ロジック（NowPlaying / AIUsage / Providers /
PresetStore / WidgetRegistry）は全部引き継ぐ。

### 検証済み事実（PoC 実測、`~/tmp/nook-poc`）

| 項目 | 結果 |
|---|---|
| 既存 `@main struct App` + `@NSApplicationDelegateAdaptor` に低レベル `Nook` だけ差し込む | **可**（`NookApp.main()` を呼ばずに動作。docs に記載のない使い方） |
| 半画面パネル（画面上半分全体、level 33）がクリックを食うか | **食わない**。`.contentShape(NookShape)` が AppKit のヒットテストまで効き、可視形状の外は透過。DynamicNotchKit Issue #48 は再現せず |
| `configureWindow` で `showInAllSpaces` を再現できるか | **可**。ただし窓が作り直されるたびリセットされるので `onExpand`/`onCompact` から毎回再適用が必要 |
| `AppState` の名前衝突 | 起きない（自モジュール優先で解決） |
| 疑似ノッチの実寸（非ノッチ機） | **300 × 30pt**。実ノッチは 185〜208pt |

### vendoring した理由

疑似ノッチ幅 `arbitraryWidth = 300`（`NSScreen+Extensions.swift:53`）は internal 定数で、
`screenProvider` / `configureWindow` / `NookStyle` のいずれからも変更できない。
かつ NookKit の UI 部品（`NookTopBar` は internal で構造固定、モジュール切替は横並び
アイコンバーではなく Menu ポップアップ、ステータスは全幅バナー、バッテリー/WiFi/BT の
部品は皆無）が Atoll 風 UI の要件に合わず、どのみち UI を自作するため NookKit を使う
実利が小さい。NookSurface は 2,617行・外部依存ゼロ・MIT なので取り込みコストが低い。

### Phase A タスク（基盤置換 / 見た目は現行維持）

- [x] A0: デッドコード削除（`NotchExpandedView` 223 / `NowPlayingMorphContent` 244 / `MetalLiquidBlobView`+`LiquidBlob.metal` 54 / `IslandCardContainer` 13 / デッド Defaults 5件 / 効かない animationSpeed Slider / KeyboardShortcuts 依存）**実績 -590行**
- [x] A1: macOS 15 Sequoia 引き上げ（pbxproj 4箇所 + CLAUDE.md + README）。Homebrew Cask は別リポジトリなので配布時に対応
- [x] A2: `perch/Vendor/NookSurface/` に **21ファイル / 2,647行**取り込み（プランの見積 19/2,617 は誤り、実測が正）+ THIRD_PARTY_NOTICES.md に帰属追記
- [x] A3: vendored の改変3点 — 疑似ノッチ幅を可変化（既定 195pt）/ `notchSize`・`menubarHeight` を public 化 / `NookHoverBehavior.expandsOnHover` 追加 + 改変を守るテスト
- [x] A4: `NookBridge` / `IslandSurfaceDriving` / `IslandChromeStyle` / `WidgetSizeMetrics` / `ScreenLocator` 追加 + テスト（3タスクに分割して実施。詳細は下記）
- [x] A5: `perch/Island/` 旧7ファイル削除 + AppState 縮退 + UI シェル層削除
- [x] A6: 既存テストの改廃（`IslandGeometryTests` / `NotchDetectorTests` 全削除、`AppStateTests` / `IslandPresentationTests` 改廃）+ A5 レビュー積み残し4件の回収

#### A4 の内訳（サブエージェント駆動 + 二段レビューで実施）

| # | 内容 | コミット |
|---|---|---|
| A4a | `IslandChromeStyle`（2値化 + `migrating(fromLegacy:)` + `nookPresentation`）/ `WidgetSizeMetrics`（`[WidgetSize: CGFloat]` 重複の一本化） | `b9b6aef` `aeb29b9` |
| A4b | `ScreenLocator`（OpenNook `NookScreenLocator` を Apache-2.0 のままコピー、`NookDisplayStore` は Defaults と二重管理になるので持ち込まず） | `0543157` `8293663` `8fb3d6c` |
| A4c | `IslandSurfaceDriving`（Kit 型を含まない seam）/ `NookBridge`（auto-collapse + window chrome 再適用）+ `FakeIslandSurface` | `10cf27e` `a7314d6` `f8e20b0` `2c3b6bf` `86ef617` |

#### A4c のレビューで潰した実バグ（4ラウンド / 指摘18件）

vendored の状態遷移を `onExpand`/`onCompact` の2本だけで捉えると穴が空く、というのが共通の根。

| # | 症状 | 原因 |
|---|---|---|
| C1 | `showInAllSpaces = false` なのにディスプレイ抜き差しで島が全 Space に出る | `observeScreenParameters` → `rebuildVisibleWindow` は `state` を変えないので `onExpand`/`onCompact` が来ず、`NookPanel` が無条件で入れる `.canJoinAllSpaces` が復活する。bridge 側で `didChangeScreenParametersNotification` を購読して二重適用 |
| C2 | 島を hide した数秒後に compact ピルがゾンビ復活 | `state = .hidden` は `onHide` を呼ぶ（`onCompact` ではない）。未購読だと `isSurfaceExpanded` が `true` のまま残り、直後の `isHovering = false` が collapse を予約 → `compact()` が窓を作り直す |
| C3 | compact コンテンツ両側無効時に `onSurfaceCompacted` が永久に来ない | `_compact` が `.compact` を経由せず `_hide` に落ちる。`onSurfaceHidden` を別イベントとして新設（hidden を compact に丸めない） |
| I4 | 表示ディスプレイ選択が丸ごと死ぬ | `screenProvider` seam が無く常に `NSScreen.main` フォールバック |
| N1 | ピル→カード展開のたびに島が一瞬消える | `skipIntermediateHides` は既定 `false` で、conversion が `.hidden` を経由する。この中間 hide を終端 hide として報告していた |

**得られた教訓**: N1 の一次修正は「hide 報告を1ホップ遅延して後続遷移で取り消す」だったが、実物の中間 hide は 250ms（`settleAnimationDuration * 0.625`）MainActor を手放すので**遅延方式は構造的に機能しない**。fake が dip を同期実行していたためテストだけが緑になっていた。fake に `await Task.yield()` を入れた瞬間に fail/pass が両方出てレースが可視化され、`drive(_:)` による**状態ベース**（`await body()` の戻りで判定）に作り直して解決。**fake の忠実度が足りないと、実物に効かない防御が緑のテストで保証されているように見える。**

#### A5: 配線 + 旧層削除 + AppState 縮退（13コミット、2段レビュー×2ラウンド）

`AppDelegate` に vendored `Nook` + `NookBridge` を差し込み、旧 `perch/Island/` 7ファイル（641行）と UI シェル層（`IslandGlassSurface` / `RootIslandView` / `CompactPillView` の独自クローム）を削除。`AppState.presentation` を `Nook.state` からの一方向派生に降格し、`transitionGeneration` / 110ms・500ms タイマー / サイズ計算5プロパティを全廃。

**ユーザー承認が要った設計判断**（AskUserQuestion で確認）:
- クロームは Perch 独自の浮遊カプセル（シェイプ・vibrancy・影・固定420/460pt）を廃し、vendored `NookShape`+`NookBackdrop` のノッチ形状に一本化。表示**内容**は不変、**外枠**が変わる
- コンパクト表示は左=アートワーク+タイトル／右=波形の2スロット
- 音楽なしの待機時も常にノッチ形状を表示（`AppState` に idle→hide の経路は足さない）

**レビューで潰した実バグ**:
| # | 症状 | 原因 |
|---|---|---|
| M1（致命的） | 島を開く手段がコードから消えていた | 旧 `onTapGesture` は削除済みファイルにしかなく、vendored 側も SwiftUI ジェスチャの当たり先を持たない（中央ギャップは vendored 側の描画、idle 時はスロットが0サイズ）。`NSClickGestureRecognizer` を surface の contentView に直接付ける方式に変更 |
| C-1 | ディスプレイ設定変更で島が実際には動かない | `applyChromeStyle` は値が変わらない限り vendored 側の `didSet` guard で即 return。同じ値を再適用しても窓は動かない。`relocate()` という無条件 rebuild 専用 seam を追加 |
| I-2/I-3 | 窓が作り直される経路の一部で chrome 再適用・クリックターゲット再アタッチが漏れる | 「窓を生む経路」を手で列挙するとバグる。`NookBridge.windowConfigurator` フックを追加し、`applyWindowChrome()`（既に全経路から呼ばれる）に一本化。呼び忘れというバグクラスごと消した |
| I-4 | メニューバー等クリック以外の展開経路では auto-collapse が武装されない | hover の**遷移**でしか予約しない設計だったため、カーソルが最初から島の上にない場合に予約が起きない。展開時に hover 状態を明示チェックして武装するよう修正 |
| I-5 | ディスプレイを全部外して戻すと島がアプリ再起動まで復活しない | `compact()` は解決画面が nil だと黙って return。screen 変更通知で `hasLiveWindow` を見て再投入する復帰経路を追加 |

**得られた教訓（2回目）**: fake が実物より寛容だと（例: 値が同じでも無条件で rebuild する）、テストは通るのに実物では効かない防御ができる。A4c の N1 と同じパターンが `applyChromeStyle` の fake 実装で再発した（C-1）。**「窓を生む経路」のようなイベント駆動の副作用は、手で列挙して各所から呼ぶより、単一の再適用関数に一本化して『呼び忘れられない』構造にするほうが安全。**

#### A6: テスト改廃 + A5 積み残し4件の回収（4コミット）

設計書のテスト改廃要求（`IslandGeometryTests`/`NotchDetectorTests` 全削除、`AppStateTests`/`IslandPresentationTests` の書き換え）は A5 側で先行完了しており、A6 での追加対応は不要だった。

A5 最終レビューの Minor 積み残し4件を回収:
- **N-1/N-2**: fake の `applyChromeStyle`/`applySyntheticNotchWidth` が hidden 中の値更新を飛ばしていた（vendored は格納プロパティなので代入は常に起きる、guard は rebuild だけをスキップ）。加えて既存のトートロジーテスト（chrome 再適用の副作用を見るだけで rebuild 有無を見ていない）を rebuild カウンタで実効化
- **N-3**: `scheduleCollapse` の sleep 明け再チェックに `!isHovering` を追加。当初想定したシナリオ（hidden→expand で必ず誤武装）は既に別ガードで塞がれていたが、実際の穴は「武装後にカーソルが島に戻っても `.onHover` イベントが欠落するとキャンセルされない」側だった
- **N-4**: `restoreSurfaceIfLost` が `isSurfaceVisible` を見ずに `hasLiveWindow` だけで復帰させていた。将来 hide 経路が使われたときユーザーが明示的に消した島を復活させる潜在バグ

テスト190件全パス。`perchUITests` の `CFBundleIdentifier` 未読み込みバグ（既存・A0以前から）は原因（`INFOPLIST_FILE` 手書き plist に bundle 系キー欠落）を特定したが、Phase A スコープ外として未修正。

**Phase A（A0〜A6）完了。** Island 層は独自実装からvendored `NookSurface` + アダプタ層（`NookBridge`/`IslandSurfaceDriving`/`ScreenLocator`/`IslandChromeStyle`）に完全移行。次は Phase B（Atoll 風展開UI）。

#### A0〜A3 で判明した追加事項

- **lefthook の pre-commit が `swift-format format --in-place` + `stage_fixed: true` を走らせる。**
  vendored ファイルが意図せず整形されたため `lefthook.yml` と CI lint の両方で
  `perch/Vendor/**` を除外した。上流との同一性は
  `diff -rq <upstream>/Sources/NookSurface perch/Vendor/NookSurface` で常に検証できる
- `.swift-format-ignore` は swift-format 602 でディレクトリを明示指定した場合に効かない。
  CI 側は `git ls-files '*.swift' | grep -v '^perch/Vendor/' | xargs swift-format lint` で回避
- **`perchUITests` は `perch.app` の `CFBundleIdentifier` を読めず失敗する既存バグがある。**
  ソースの `Info.plist` に当該キーが無いのが原因で、A0 の変更前から再現する（stash して確認済み）。
  Phase A のスコープ外だが、UI テストを実際に書く前に解消が必要。
  当面の検証は `xcodebuild test -only-testing:perchTests` で行う

### Phase B タスク（Atoll 風展開UI）— **完了**

**Branch**: `feat/expanded-ui-redesign`
**Last Updated**: 2026-07-30

`/hallmark` と `/ui-ux-pro-max` を必ず適用。Atoll の OSS 版は **GPL-3.0 なのでソースは読まない**
（読むこと自体が派生物認定のリスク）。スクリーンショットから読み取れるレイアウト構造の
着想のみ参考にし、視覚言語は Perch 独自にする。

B4（NowPlaying 再デザイン）は次の NowPlaying フェーズへ、B6（File Shelf）は Phase 4 へ、
B7（Timer）は対応フェーズ未定のまま保留として切り出し、それ以外を Phase B の完了条件とした
（監査・ユーザー確認: 2026-07-30）。

- [x] B1: `IslandTopBar` — 左にモジュールアイコン列、右にステータスクラスタ
- [x] B2: `SystemStatusCluster` — バッテリー（IOKit、権限不要）/ WiFi（CoreWLAN、**SSID は出さない**＝ Location 権限を回避）。
      **仕様変更**: Bluetoothは撤去した。SF Symbols に公式 Bluetooth ロゴが存在しないことを
      ユーザーが SF Symbols アプリで直接確認（Bluetooth SIG の商標のため未収録という説と一致）。
      代替アイコンで妥協せず、バッテリー＋WiFiの2点のみに確定
- [x] B3: モジュールルーティング。**新規 `PerchModule` enum は作らず**、Phase A で「モジュール
      バーが選ぶ対象」として温存済みの `IslandCard` を再利用（当初の設計意図と一致する代替実装）
- [x] B4: NowPlaying 展開の再デザイン（既存 `NowPlayingCard.swift` 374行の資産を活かす）—
      当初「次の NowPlaying フェーズへ移管」としていたが、**2026-07-30 に「Phase B4+」
      として本格着手・完了**（詳細は下記セクション参照）
- [x] B5: `compactLeading` のレジストリ駆動化（`pillPrimary` を配線）。**`compactTrailing`
      （`pillSecondary`）は意図的に見送り** — waveform が生の音声キャプチャ状態（
      `AudioCaptureService.rmsLevels`）に直接依存しており、`PerchWidget` プロトコルの
      静的な `body(size:)` では表現できないため。将来別の何かを trailing に出したくなった
      時に改めて設計する
- [ ] ~~B6: File Shelf モジュール~~ — **Phase 4（File Shelf, v0.4）と完全に重複していたため
      Phase B のスコープから削除。Phase 4 に一本化**
- [ ] B7: Timer モジュール — 対応する既存フェーズなし。保留（優先度低）

> モジュール（ホーム / AI Usage、将来 File Shelf / Timer）とプリセット（Daily / Dev）は
> **別概念**。上部バーはモジュール、プリセットは Minimal モードのホームモジュール内の
> ウィジェット配置としてのみ残る（後述の UIMode 参照）。

### Phase B スコープ追加（実装中のユーザー指摘により追加、当初の B1〜B7 に無かったもの）

ユーザーが実機でテストしながら「あれもこれも」と指摘した結果、当初の Phase B 計画
（B1〜B7）には存在しなかった作業が生まれた。今後同じことが起きないよう、
`CLAUDE.md` に「追加依頼は progress.md に明記してから着手する」運用ルールを追加した
（本追記はその運用ルール施行前の事後記録）。

- [x] hover展開（compact pill にカーソルを乗せると開く、300ms debounce） —
      クリックしないと展開しない、という指摘への対応
- [x] hover専用の短い収縮遅延（`hoverCollapseDelay`、100ms）—
      hover離脱で閉じない、という指摘への対応。既存の `autoCollapseDelay`
      （1〜10秒、ユーザー設定）とは別物として新設し、hoverなしで展開された場合の
      保険としてのみ `autoCollapseDelay` を残した
- [x] 背景を常時ソリッド黒に（`.vibrancy(darkenOpacity: 0)` → `.solidBlack`）—
      ノッチが透明に見える、という指摘への対応
- [x] compact角丸を Atoll 風にパッチ（vendored `NookStyle`/`NookView` の改変4点目・5点目）
- [x] バッテリー SF Symbol 名の修正（`battery.0` → `battery.0percent` 系）—
      前回実装時に SF Symbols アプリで実名確認せず推測で命名していたミスの修正
- [x] **`UIMode` 設定（Rich/Minimal）** — Atoll 風のリッチなデフォルト画面と、既存の
      preset 駆動ウィジェット一覧（Minimal）を切り替えられるように、という指摘で新設。
      **当初の Phase B 計画（B1〜B7）に存在しない新機能**
- [x] **`CalendarWidget`/`CalendarStore`（EventKit）** — Atoll のデフォルト画面にある
      カレンダーも欲しい、という指摘で新設。**当初の Phase B 計画に存在しない新機能**。
      Mirror（カメラプレビュー）は同じ指摘の中でスコープ外と確認済み
- [x] Shell開閉の非対称バネ（`DesignSystem.shellOpen`/`shellClose`、
      `Nook.transitionConfiguration` 経由）— アニメーションを Atoll 動画のように
      洗練させて、という指摘への対応。`/vfr` で参考動画のキーフレームを抽出したが
      解像度・圧縮の都合で正確なバネ係数は読み取れず、ハンドブック自身の推奨値を採用

### Phase B4+: B4完遂 + Atoll風UI寄せ（2026-07-30〜）

**Branch**: `feat/expanded-ui-redesign`
**Last Updated**: 2026-07-30

Phase Cに進む前に、Phase Bで積み残していたB4（NowPlaying展開の再デザイン）に本格着手。
着手にあたり、ユーザーが実機を触りながら追加の不満点をまとめて提示したため、B4単体では
なく「Rich modeホーム画面全体をAtoll風に寄せる」作業として範囲を確定した
（CLAUDE.md運用ルールに従い、着手前に本節として明記してから着手）。

設計の詳細・判断背景は `docs/superpowers/specs/`（未作成の場合はプラン file
`phasec-phaseb-b-docs-playful-cocoa.md` 相当の内容）を参照。

- [x] BP1: 設定画面が開かないバグ修正（最優先）— `MenuBarController.openSettings()` が
      `NookPanel`（Island自体の常駐クロムウィンドウ、`canBecomeKey: true` かつ常時
      `isVisible: true`）を誤って「最初のkeyable+visibleウィンドウ」として掴んでしまい、
      本物のSettingsウィンドウにフォーカスできていなかったのが真因。`SettingsWindowSelector`
      という純粋関数に選定ロジックを切り出しNookPanelを除外
- [x] BP2: モジュールアイコン差し替え — `.nowPlaying`(Home相当)を`music.note`→`house.fill`、
      `.aiUsage`を`sparkles`→`chart.bar.horizontal.page`、`.fileShelf`を`tray`→
      `square.and.arrow.up.on.square`（将来のFile Shelf用、未到達のまま）。Timer用
      `"timer"`はコメント予約のみ（対応するIslandCaseは無い、B7が保留中のため新規case追加せず）
- [x] BP3: Rich modeホームからAIUsageフォールバック除去 — `AtollStyleExpandedView.mainActivity`
      がNowPlaying無し時に`AIUsageStandardView()`を暗黙表示していた実装を、新規`NoActivityView`
      （素直な空状態）に置き換え。AI Usageは`ModuleSwitcher`経由の独立画面(`AIUsageFullView`)
      として引き続きアクセス可能
- [x] BP4: NowPlayingCard再デザイン + 3カラム化（B4本体）— Rich mode展開画面を
      「左=NowPlayingCard(大アートワーク化)／中央=歌詞(複数行、Perch独自のこだわり)／
      右=CalendarWidget」の3カラムに再構成。Mirror（カメラプレビュー）はAtoll機能だが
      実装しないと確認済み（Phase Bスコープ追加時点で既にスコープ外）——ただしその分の
      余白は捨てず中央カラム(歌詞)に転用する、という設計判断
  - [x] BP4-1: `CalendarMonthGrid`新規（EventKit非依存の純粋日付計算構造体）+ テスト
  - [x] BP4-2: `CalendarWidget`ホバーグリッド統合（カーソルなし=シンプル表示、
        ホバー中=月間グリッド表示にクロスフェード）
  - [x] BP4-3: `NowPlayingLyricsColumn`新規切り出し（歌詞取得ライフサイクルを
        `NowPlayingCard`から`AtollStyleExpandedView`に引き上げ）+ 全画面歌詞表示
        (`lyricsFullView`)削除（中央カラムに常時複数行歌詞が出るため重複と判断、
        ユーザー確認済み）。実装中に`NowPlayingCard`は`NowPlayingWidget`経由でMinimal
        modeのプリセットウィジェットとしても使われていたことが判明（計画時の見落とし）。
        ユーザー確認の上、Minimal modeでは歌詞なしとし、歌詞はRich modeの専用カラムに
        一本化する方針に決定
  - [x] BP4-4: `NowPlayingCard`横長レイアウト再構成（大アートワーク化、歌詞出し分け
        ロジック撤去で単純化）。shuffleボタンは追加しない（既存API無し、スコープ外と確認済み）
  - [x] BP4-5: `AtollStyleExpandedView`の3カラムHStack配線
  - [x] BP4-6: `ExpandedIslandView`の展開幅を条件分岐（Rich mode+presetDriven時のみ
        `minWidth`をAtoll相当(680pt、`DesignSystem.richModeMinWidth`にトークン化)に拡大。
        Minimal mode/AIUsage直行画面は既存420ptを維持）
- [x] BP5: コンパクトピル（未展開状態）— ユーザー確認の結果、現状維持でスコープ外
      （2026-07-30 AskUserQuestionで確認：「ノッチを開いてない状態」の理解で合っており、
      変更不要と回答）

### Phase D: バッテリー監視・アニメーション本格実装（未着手・タスク分割のみ）

**参照**: `docs/macOS-Battery-Monitoring-Animation-Handbook-ja.md`（全39章、
§0設計原則〜§38チェックリスト）
**現状**: `perch/UI/SystemStatusCluster.swift` + `perch/Core/SystemStatus/SystemStatusIcons.swift`
の素朴な閾値分岐（`battery.0percent`〜`battery.100percent` / `battery.100percent.bolt`）のみ。
IOKit直読み・HUD調停・常設/一時アニメーションは未実装。
**2026-07-30 追記**: Phase B4+着手に伴うユーザー指摘で新フェーズとして切り出し。
ハンドブックの章立てをそのままタスク化せず実装順として妥当な粒度にグルーピング。
**このフェーズ自体はまだ実装に着手しない**（タスク分割の記録のみ）。

- [ ] D1: IOKit Reader基盤 — `IOPowerSources`/`IOPSCopyPowerSourcesInfo`経由のバッテリー
      状態リーダー新設。充電状態・残量・推定残り時間・サイクルカウント等のデータモデル定義
- [ ] D2: HUD調停・表示ポリシー — システム標準バッテリーHUDとPerch常駐表示の競合回避、
      常設表示と一時的な状態変化アニメーションの分離設計
- [ ] D3: アニメーション実装 — 充電開始/完了・低残量警告・急速充電など状態遷移ごとのモーション
- [ ] D4: テスト・検証 — IOKit読み取り結果→SF Symbol/表示状態マッピングを純粋関数として
      切り出しユニットテスト化。実機（充電/放電両方）での長時間検証チェックリスト作成

### Phase E: WiFi拡張（テザリング/デュアルSIM検知、未着手・タスク分割のみ）

**現状**: `perch/UI/SystemStatusCluster.swift` + `perch/Core/SystemStatus/WiFiMonitor.swift`は
`CWWiFiClient.shared().interface()?.powerOn()`によるWiFi電源ON/OFFの2値判定のみ
（`SystemStatusIcons.wifiSymbolName`も`wifi`/`wifi.slash`の2値）。SSIDは意図的に未取得
（Location権限回避、B2の既存方針）。
**2026-07-30 追記**: Phase B4+着手に伴うユーザー指摘で新フェーズとして切り出し。
テザリング検知時`cellularbars`、デュアルSIM検知時`cellularbars.short.cellularbars`を
出したいという要望だが、**このフェーズ自体はまだ実装に着手しない**（タスク分割の記録のみ）。

- [ ] E1: 検知手段の調査（実装着手前に必須）— macOSにはiOSのようなネイティブSIM/セルラー
      APIが存在しない。`NWPathMonitor`（Network framework）でインターフェース種別を見る
      方法はあるが、確実なテザリング判定にはSSIDパターン照合が必要になりやすく、既存の
      「SSID非取得」方針（Location権限回避）と衝突する可能性がある。この矛盾を先に解消する
      設計判断が必要。デュアルSIM検知はMac側からは原理的に情報が取れない可能性が高く、
      取得可能な情報の有無を先に技術検証してから実現可否を判断する
- [ ] E2: 実装（E1の結論次第で着手）— テザリング検知時`cellularbars`を追加。デュアルSIM
      検知が技術的に可能と判明した場合のみ`cellularbars.short.cellularbars`を追加
- [ ] E3: テスト — 新しい判定ロジックも`SystemStatusIcons`と同様、外部依存を持たない
      純粋関数として切り出しテスト可能にする

### Phase C タスク（波形の実音キャプチャ修理）

**原因はすべて特定済み。** 現状は ScreenCaptureKit のアプリ別音声キャプチャで、以下が壊れている:

| # | 箇所 | 内容 |
|---|---|---|
| 1 | `NowPlayingManager.swift:415-419` | `ytmBrowserBundleId` が「起動中の最初のブラウザ」の当てずっぽう。Safari 常駐時は Chrome の YTM を永久に拾えない。正しい bundleId は `MediaRemoteBridge.swift:53` にあるのに `NowPlayingState.swift:276` が捨てている |
| 2 | `NowPlayingManager.swift:478` | `.mrMediaRemote` は `captureBundleId = nil` → **この経路では実音波形が構造的に一度も動かない** |
| 3 | `AudioCaptureService.swift:73` | `SCStream(delegate: nil)` でストリーム死亡を検知できず、`:34` の guard で再接続が永久ブロック |
| 4 | `AudioCaptureService.swift:132-138` | デコードエラーの完全握りつぶし（`AudioPCMDecoder` は6種の `LocalizedError` を定義しているのに一件も表に出ない） |
| 5 | `AudioCaptureService.swift:33-35` | `startCapturing` に再入ガードなし。孤児 SCStream が残りうる |

`WaveformView.swift:41-69` が失敗時に合成波形へフォールバックするため、**壊れていても
「滑らかに動いている」ように見え、成功と区別がつかない**。git log にも
`88e744f fix: pure synthetic waveform`（一度降参）→ `4cdcddd`（実音に再挑戦）→
`87172f0 fix: gate waveform levels on hasReceivedAudio`（実音が来ない前提のゲート追加）
という往復が残っている。**原因に手を付けないままゲートで隠したのが再発の構造的理由。**

- [ ] C0: 切り分け — `:132` の catch にログ / `:38` の `content.applications.count` をログ / **Spotify で試す**（bundleId が正しいので、動けば YTM のブラウザ誤選択が犯人と確定）
- [x] C1: `NowPlayingState` に `sourceBundleId` を追加し MediaRemote の bundleIdentifier を伝搬（2026-07-30）
- [x] C2: `ytmBrowserBundleId` の当てずっぽうを削除（2026-07-30）
- [ ] C3: `.mrMediaRemote` でもキャプチャする
- [ ] C4: `SCStreamDelegate` 実装（`didStopWithError` で再接続可能に）
- [ ] C5: エラーを握りつぶさずログ
- [ ] C6: `startCapturing` の再入ガード
- [ ] C7: **BF4 回収** — `CGPreflightScreenCaptureAccess` / `CGRequestScreenCaptureAccess` + 拒否時の Settings 導線
- [ ] C8: **診断表示** — Settings に「波形が実音か合成か」を出す。再発を即座に検知できるようにする
- [ ] C9: テスト追加（`AudioPCMDecoder` 各フォーマット / `AudioSpectrumAnalyzer` 既知入力 / `WaveformView.blendedLevels` の3分岐）。**現状 Audio 系のテストはゼロ**

### Phase C スコープ追加: Kaset.app（ネイティブYTMクライアント）のNow Playing検知対応（2026-07-30・実機検証完了）

ユーザーからの追加依頼（CLAUDE.mdの運用ルールに従い、着手前に本節として明記）。
[Kaset](https://github.com/sozercan/kaset) は YouTube Music を Apple Music 風のネイティブ UI で
再生できる macOS アプリ。深夜作業中に着手し未完了・コンパイルエラーありの状態で残っていた差分
（`chromiumBrowsers`→`youtubeMusicApplications` のリネーム、Kaset の bundle id 追加、
`sourceBundleIdentifier` フィールド追加）を引き継ぎ、実機での6ラウンドの反復検証を経て
最終的に正しく動作することを確認した。

- [x] Kaset の bundle identifier確認。GitHub上の `Info.plist` の `CFBundleURLName`
      （`com.sertacozercan.kaset`、小文字k）は**罠**で、実際のbundle identifierは
      `Scripts/build-app.sh:16` の `BUNDLE_ID="com.sertacozercan.Kaset"`（大文字K）。
      `CFBundleURLName` はURLスキーム登録名の一種にすぎず、bundle identifierと
      一致するとは限らない
- [x] `NowPlayingManager.chromiumBrowsers` を `youtubeMusicApplications` にリネーム
      （宣言含め全参照箇所を修正）+ Kaset を追加。ブラウザに限らない「YTM 相当の
      MediaRemote 発行元」という位置づけに変更
- [x] `.youTubeMusic` は新規 `MusicSource` ケースを作らず既存のものへ統合（既存の
      `enableYouTubeMusic` トグル・優先度ロジックをそのまま流用）
- [x] Phase C の C1/C2 をこのタスクの前提として先取り実施（複数の YTM 発行元が同時に
      起動している場合の当てずっぽうバグを解消しないと Kaset 追加自体が不安定になるため）
- [x] `applyState` のアートワーク carry-forward パスが `sourceBundleIdentifier` を
      引き継いでいなかった実バグを発見・修正
- [x] **Kaset側のアーキテクチャに起因する実バグを発見・修正**（実機検証で判明、
      Kasetのソース `Sources/Kaset/Services/Player/NowPlayingManager.swift` の
      `desiredClaim` を直接読んで特定）: Kasetは内部で実際のYouTube MusicページをWKWebViewで
      描画しており、**再生中は自分のbundle id（`com.sertacozercan.Kaset`）では
      Now Playing情報を発行しない**（`.playing/.buffering/.loading` → `.handsOff`）。
      再生中の本物のメタデータは埋め込みWebKitヘルパープロセス
      （`com.apple.WebKit.GPU` 等、macOS共有のシステムプロセスでSafari等とbundle id共有）
      が発行し、Kaset自身のbundle idは一時停止/ロード中のフォールバック情報のみを出す。
      これに対応するため:
      - `MediaRemoteBridge.bundleIdentifierFilter`（`(String?) -> Bool`）を
        `bundleIdentifierResolver`（`(TrackInfo.Payload) -> String?`）に設計変更。
        単なる許可/拒否ではなく「どのbundle idに帰属させるか」を返す形に一般化
      - `NowPlayingManager.resolveBundleIdentifier` という `static` 純粋関数を新設。
        `com.apple.WebKit.` prefixのイベントは、`payload.applicationName` が
        既知アプリの表示名で**前方一致**する場合のみ、そのアプリの本来のbundle idに
        正規化して受理する（`com.apple.WebKit.GPU`をそのまま許可リストに加えると
        Safari等の無関係なWebページ音声まで誤検知するため危険 — 却下した設計案）
      - `applicationName` は実測で `"Kaset Graphics and Media"` のような
        `"<アプリ名> <コンポーネント説明>"` 形式で、完全一致ではなく `hasPrefix` が必要
        だったことも実機ログで確定（最初は完全一致で実装し、1ラウンド無駄にした）
      - `NowPlayingState.init?(fromMediaRemote:)` に `overrideBundleIdentifier` を追加し、
        正規化後のbundle idを `sourceBundleIdentifier` として使うようにした
- [x] swift-logの `Logger.logLevel` はインスタンスごとにデフォルト `.info` で `.debug` ログが
      握りつぶされる問題を発見・修正（`LoggingSystem.bootstrap` 未使用のプロジェクトでは
      各 `Logger` 生成直後に `logLevel = .debug` を明示設定する必要がある）
- [x] 副次的に発見した設定画面が開きにくい問題を修正: `MenuBarController.openSettings()` の
      単発100ms sleepを、50ms×最大10回のポーリングに変更（`docs/progress.md` 既知の
      macOS 14+ Settings起動タイミング問題の系譜、Phase 2c-fix/2e T3/2f T0 と同種）
- [x] テスト追加: `NowPlayingStateTests`（`sourceBundleIdentifier` の伝搬・Equatable差分）、
      `NowPlayingManagerTests`（`matchesTerminatedApp`・`resolveBundleIdentifier` を
      `static` 純粋関数として切り出し単体テスト。WebKitヘルパー経由の正規化・
      前方一致・未知アプリ拒否を含む）
- [x] 実機で3曲以上の切り替えを含む複数ラウンドの検証を実施し、タイトル・アートワークが
      正しく更新されることを確認済み

**既知の制限**: `applicationName` の前方一致判定はKaset固有の内部文字列
（`"Kaset Graphics and Media"`）に依存する reverse-engineered な挙動であり、
Kaset側のアップデートで表示名パターンが変わると再度壊れうる。公式に保証された仕様ではない。

### 将来（Phase 4）: Core Audio Taps への載せ替え

Phase C で SCK が直っても、**macOS 15 以降のオレンジ収録インジケータ常時点灯と定期的な
権限再確認ダイアログは残る**（`com.apple.developer.persistent-content-capture` entitlement は
特別承認が必要で一般アプリには下りない）。常駐アプリとして痛いので Core Audio Process Taps
（macOS 14.2+）に載せ替える。インジケータなし・仮想デバイス不要。見積 8〜11人日。

参照実装は **AudioCap (BSD-2)** と **iqualize (MIT)** のみ。boring.notch / Atoll は GPL-3.0 で参照不可。
（参考: boring.notch 10k★ の波形は `CGFloat.random(in: 0.35...1.0)` の純乱数）

既知の罠: `isExclusive` を触ると無音 / アグリゲートは「実出力デバイス=main、tap=sub-tap、
`TapAutoStart=true`」でないとエラーなしのゼロサンプル / `AVAudioEngine` への retarget は
`noErr` を返すのに既定入力を読み続ける / IOProc の queue に `nil` を渡すと macOS 26 で
サイレント失敗 / 署名なしビルドでは TCC ダイアログがそもそも出ない / macOS 26 に
「長時間稼働で全サンプルが 0 になる」未解決 OS バグ（Apple Forums #825780、Apple 未回答）
→ 連続ゼロ検知でタップ+アグリゲートを両方破棄して再作成するウォッチドッグ必須

### 既知の制限 / 仕様変更

- **hover で自動展開する**（`Nook.updateHoverState` が無条件で `_expand` を呼ぶ）。従来はタップのみ。vendoring したのでオプション化は可能だが、Phase A では既定挙動を受け入れる
- **「外側クリックで即収縮」が無くなる**（hover 展開と喧嘩するため）
- **`Defaults[.pillSize]` を削除**。`.notch` 固定にすると floating pill の概念が消え、高さは
  `notchSize.height`、幅は content-driven になるため設定の意味が失われる
- **同じ Perch でもマシンによってノッチ幅が変わる**（実ノッチ機は実寸、非ノッチ機は疑似 195pt）
- `perchUITests/` は Xcode テンプレートのまま実質空。UI リグレッションは手動チェックリスト
  （設計書の E-1 節）で担保する
