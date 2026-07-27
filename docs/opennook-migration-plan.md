# Perch 大改造計画 — OpenNook(vendored) 移行 + Atoll 風展開UI + 波形修理

## Context

### なぜやるか

Perch は現在、コンパクトピルもノッチ融合表示も `perch/Island/`（595行）で完全に独自実装している。結果:

- **UI が破綻している** — `RootIslandView` が NowPlaying の有無で2経路に分岐し、それぞれ別のガラス実装・別のタップハンドラ・別のサイズ源を持つ。形状ロジックは3箇所に重複。ノッチ検出は `NotchDetector` と `ScreenEnvironment` に二重実装され、実際に使われているのは後者だけ。
- **回避策の塊** — `IslandWindow.setFrame` を override して SwiftUI のフレーム要求を握り潰す、`NSHostingView.sizingOptions = []`、`transitionGeneration` と 110ms/500ms のマジックナンバー、CALayer cornerRadius の手動同期 — すべて「AppKit の透明ウィンドウに SwiftUI を載せる」ことに起因する自作の対症療法。
- **ノッチ活用アプリとして成立していない** — 非ノッチ Mac では浮かぶピルになり、マシンで見た目が変わる。Atoll のような統一感がない。
- **波形が実音に連動していない** — ユーザー申告「前も同じ問題に引っかかって、症状まで一緒」。原因は特定済み（後述）。

### 到達点

3フェーズで、Island 層を vendored OpenNook に載せ替え、展開UIを Atoll 級に作り直し、波形を実際に鳴らす。機能ロジック（NowPlaying / AIUsage / Providers / PresetStore / WidgetRegistry）は全部引き継ぐ。

### 確定した判断（ユーザー承認済み）

| 論点 | 決定 |
|---|---|
| Kit | **NookSurface を vendoring**（2,617行 / 19ファイル / MIT / 外部依存ゼロ）。NookKit は使わない |
| macOS 最小 | **14 → 15 Sequoia** |
| 表示モード | 既定 `.notch` 固定（Atoll 風、全マシン統一）。Settings は「ノッチ風 / 浮かべるピル」の2択 |
| 疑似ノッチ幅 | **実ノッチ相当（185〜208pt）に変更**。vendoring したので可変にできる |
| hover 展開 | Phase A では受け入れる（Kit の既定挙動） |
| 波形 | **段階的** — Phase C で ScreenCaptureKit を修理、後日別PRで Core Audio Taps へ |
| フェーズ分割 | **A: 基盤置換 → B: Atoll 風UI → C: 波形**。各フェーズで PR、間で `/clear` |

---

## 確認済み事実（PoC 実測 + 実ソース読解）

PoC は `~/tmp/nook-poc`（捨てプロジェクト、Perch には未コミット）で実施。

### PoC 結果

| # | 項目 | 結果 |
|---|---|---|
| (a) | 既存 `@main struct App` + `@NSApplicationDelegateAdaptor` に低レベル `Nook` だけ差し込む | **緑** — `NookApp.main()` を呼ばずにビルド・起動・表示すべて成功 |
| (a') | 半画面パネルがクリックを食うか | **緑** — `[window] NookPanel frame=(0,525,1680,525) level=33 ignoresMouse=false` に対し `topLeft=pass topRight=pass leftOfNotch=pass rightOfNotch=pass midUpper=pass insideNotch=BLOCKED`。`.contentShape(NookShape)` が AppKit のヒットテストまで効く。DNK Issue #48 は再現しない |
| (d) | `configureWindow` で `showInAllSpaces` 再現 | **緑** — `applied (joinsAllSpaces=true)` |
| (e) | `AppState` 名前衝突 | **緑** — 自モジュール優先で解決 |
| (g) | hover 展開・自動収縮 | **緑**（ユーザー実機確認済み） |
| (i) | 疑似ノッチ実寸 | **300 × 30pt**（非ノッチ機）。実ノッチは 185〜208pt |

### ソース読解で判明した制約

1. **`notchSize` / `menubarHeight` は internal** — ホストから読めない（`Nook.swift:116-117`）
2. **`NookStyle` に `.auto` は無い** — `.standard`（topCornerRadius 15 / bottom 20）のみ。notch↔floating は `presentation` だけが担う
3. **hover 展開は無効化不可**（SPM 依存のままなら）— `Nook.swift:401-425` の `updateHoverState` が無条件で `_expand` を呼ぶ。`hoverBehavior` は haptic と keepVisible しか制御しない。`staysExpandedOnHoverExit` は hover-*out* 側のみ
4. **サイズを渡す seam が無い** — `initializeWindow` が `NSSize(width: screen.frame.width, height: screen.frame.height / 2)` 固定。可視形状は `NookShape` の clip、サイズは `.fixedSize()` の content-driven
5. **疑似ノッチ幅は `arbitraryWidth: CGFloat = 300`**（`NSScreen+Extensions.swift:53`、internal）。`.notch` のときだけ効く（`NookView.swift:77, 274, 306, 348`）。`screenProvider` / `configureWindow` / `NookStyle` のどれでも変更不可 → **vendoring 以外に道はない**
6. **NookSurface だけの「SPM 依存 + 部分差し替え」は不可能** — モジュール名衝突、NookKit が `Nook<AnyView,AnyView,AnyView>` を具象型で直接構築（`AppCoordinator.swift:185-186`）、`NookSurfaceDriving` が internal。だから「vendoring して NookKit を捨てる」か「全体 fork」の二択だった
7. **NookKit の既製 UI は Atoll 風に使えない** — `NookTopBar` は internal で構造固定、モジュール切替は横並びアイコンバーではなく `Menu` ポップアップ（`NookTopBar.swift:262-321`）、ステータスは全幅の横長バナー、バッテリー/WiFi/BT の部品は皆無（リポジトリ全体を grep して0件）。**どのみち自作**

→ vendoring の判断根拠: どのみち UI を全部自作するなら NookKit の価値は Shelf / ActivityQueue / ScreenLocator / HotkeyController に限られ、そのうち **Shelf モデル4ファイル(607行) と NookScreenLocator(141行) は NookKit 非依存で単独コピーできる**。

### 波形が動かない原因（すべて確認済み）

現状は **ScreenCaptureKit のアプリ別音声キャプチャ**（マイクでもフェイクでもない）。パイプラインは `AudioCaptureService`(SCK) → `AudioPCMDecoder`(PCM) → `AudioSpectrumAnalyzer`(vDSP FFT 2048点/6バンド) → `WaveformView`。壊れている箇所:

| # | 箇所 | 内容 |
|---|---|---|
| **1** | `NowPlayingManager.swift:415-419` | `ytmBrowserBundleId` が `runningApplications.first { chromiumBrowsers.contains(...) }` — **起動順の当てずっぽう**。Safari が常駐していれば Chrome の YTM は永久に拾えない。しかも正しい bundleId は `MediaRemoteBridge.swift:53` の `trackInfo.payload.bundleIdentifier` にあるのに `NowPlayingState.swift:276` が捨てて `.youTubeMusic` をハードコードしている |
| **2** | `NowPlayingManager.swift:478` | `.mrMediaRemote` ソースは `captureBundleId = nil` → `stopCapturing()`。**この経路では実音波形が構造的に一度も動かない** |
| **3** | `AudioCaptureService.swift:73` | `SCStream(delegate: nil)` — ストリーム死亡を検知できない。`:34` の `guard bundleId != currentBundleId else { return }` により**再接続が永久ブロック** |
| **4** | `AudioCaptureService.swift:132-138` | デコードエラーの**完全握りつぶし**（ログゼロ）。`AudioPCMDecoder` は6種の `LocalizedError` を定義しているのに一件も表に出ない |
| **5** | `AudioCaptureService.swift:33-35` | `startCapturing` に再入ガードなし。await 点が3つあり孤児 SCStream が残りうる |
| **6** | — | 権限拒否時の UI が無い。`CGPreflightScreenCaptureAccess` はコードベースに存在しない。`docs/progress.md:297` の `[ ] BF4` が未完了のまま |
| **7** | — | **テストがゼロ**（`rg -l "Audio|Waveform|Spectrum" perchTests` → 0件） |

そして `WaveformView.swift:41-69` の `blendedLevels` が失敗時に合成波形へフォールバックするため、**壊れていても「滑らかに動いている」ように見え、成功と区別がつかない**。git log には `88e744f fix: pure synthetic waveform`（一度降参）→ `4cdcddd feat: blend real audio with synthetic flourish`（実音に再挑戦）→ `87172f0 fix: gate waveform levels on hasReceivedAudio`（実音が来ない前提のゲート追加）という往復が残っている。**原因に手を付けないままゲートで隠した**のが再発の構造的理由。

権限まわりは正しく設定済み: `Info.plist` に `NSScreenCaptureUsageDescription` あり、`Perch.entitlements` は `app-sandbox = false`、pbxproj の紐付けも正常。ただし `scripts/run.sh` が毎回 DerivedData の `.app` を起動するため、**リビルドのたびに画面収録 TCC が実質リセットされる**環境である点は要注意。

### ScreenCaptureKit vs Core Audio Taps

| | ScreenCaptureKit | Core Audio Process Taps |
|---|---|---|
| 対応 | macOS 13+ | macOS 14.2+（実用 14.4+） |
| 権限 | 画面収録 | `NSAudioCaptureUsageDescription`（独立TCCカテゴリ） |
| **常駐時のUX** | **macOS 15 以降オレンジ収録インジケータ常時点灯 + 定期的な権限再確認ダイアログ** | **インジケータなし・再確認なし** |
| 音声のみ | 不可（ダミー映像を回す必要あり。現状 2×2px/1fps を登録済み） | 可 |
| 仮想デバイス | 不要 | 不要 |
| 参照実装 | — | **AudioCap (BSD-2)** / **iqualize (MIT、CATap+vDSP 2048点FFT+60fps描画で今回とほぼ同一構成)** |

`com.apple.developer.persistent-content-capture` entitlement は特別承認が必要で一般アプリには下りない。**常駐ノッチアプリには CATap が正解**だが、まず原因が特定できている SCK を直す（Phase C）。

参考: boring.notch(10k★) の波形は `CGFloat.random(in: 0.35...1.0)` の**純乱数**（`MusicVisualizer.swift`）。Atoll の OSS 版は **GPL-3.0 なので参照不可**（読むこと自体が派生物認定のリスク）。

---

## Phase A — 基盤置換（見た目は現行維持）

ブランチ: `feat/island-opennook-vendored`

### A-0. デッドコード削除（独立コミット）

| 対象 | 行数 |
|---|---:|
| `perch/UI/NotchExpandedView.swift`（参照0） | 223 |
| `perch/Features/NowPlaying/NowPlayingMorphContent.swift`（参照0） | 244 |
| `perch/UI/MetalLiquidBlobView.swift` + `perch/Metal/LiquidBlob.metal`（参照0、pbxproj のビルドフェーズからも削除） | 54 |
| `perch/UI/IslandCardContainer.swift`（参照0） | 13 |
| `Preferences.swift` のデッドキー `islandMode` / `windowLevel` / `displayScreen` / `showSatelliteCircle` | 4 |
| `animationSpeed` Defaults + `SettingsView.swift:82-90` の Slider + L10n（**効かない UI**） | ~12 |
| `CompactPillView.swift:79-83 formatCost` / `:15 isSatelliteVisible` | 7 |
| SPM `KeyboardShortcuts` 依存（Swift 参照0） | — |

**`WidgetLayout.swift:50-51` の `pillPrimary` / `pillSecondary` は削除しない** — Kit の compactLeading/compactTrailing 2スロットに Phase B で 1:1 対応させる。`// Phase B: maps to surface compactLeading/compactTrailing` のコメントを付す。

### A-1. NookSurface の vendoring

`perch/Vendor/NookSurface/` に 19ファイル / 2,617行をコピー。**外部依存ゼロ**（import は SwiftUI / AppKit / Combine / Foundation のみ）。

- モジュールを分けず **Perch 本体ターゲットに直接含める**（SPM の別ターゲットにすると public/internal の境界を維持する必要が出て、改変の自由度という vendoring の目的を損なう）
- 各ファイルの SPDX ヘッダはそのまま残す。改変したファイルの冒頭に `// Modified for Perch: <理由>` を追記（DNK → OpenNook が踏襲している慣行）

**必要な改変（3点のみ、いずれも小さい）**:

| # | ファイル | 改変 |
|---|---|---|
| 1 | `Internal/NSScreen+Extensions.swift:53` | `let arbitraryWidth: CGFloat = 300` を可変化。`Nook` から注入した幅を使う。既定は実ノッチ相当 **195pt**（185〜208 の中央値）とし、Defaults で調整可能に |
| 2 | `Nook.swift:116-117` | `notchSize` / `menubarHeight` を `public private(set)` に昇格（Perch 側でレイアウト計算に使う） |
| 3 | `NookHoverBehavior.swift` + `Nook.swift:401-425` | `.expandsOnHover` を OptionSet に追加（既定 on で後方互換）。Phase A では既定のまま使い、オプション化は Phase B で判断 |

**改変しないもの**: `NookShape` / `NookPanel` / `NookView` のヒットテスト・トランジション・レイアウト。PoC で正しく動くことを実証済みなので触らない。

### A-2. `perch/Island/` の処遇

| ファイル | 行 | 処遇 |
|---|---:|---|
| `IslandWindow.swift` | 92 | **削除** — `NookPanel` が上位互換。`setFrame` 握り潰しハックは Kit がサイズ交渉をしないので問題自体が消滅 |
| `IslandWindowController.swift` | 243 | **削除 → `NookBridge.swift` に縮退** — 固定NSView+`sizingOptions=[]`、レースガード、cornerRadius 手動同期、`didChangeScreenParameters` 再レイアウトはすべて Kit 内に等価物がある |
| `IslandGeometry.swift` | 63 | **削除** — content-driven sizing |
| `NotchDetector.swift` | 89 | **削除** — `perchNotchSize` は元々デッド。`perchPreferredScreen` は `NookScreenLocator`（A-3 でコピー）で代替 |
| `ScreenEnvironment.swift` | 79 | **削除** — `.auto` を使わない設計にしたので `screenHasNotch` 判定が不要 |
| `MouseEventMonitor.swift` | 69 | **削除** — `.onHover` + `isHovering` + `staysExpandedOnHoverExit` で再現（A-5） |
| `IslandMode.swift` | 6 | **削除** — `IslandChromeStyle` に統合 |

### A-3. 新規ファイル

```
perch/Island/
  NookBridge.swift            (~140行) — vendored Nook の所有者。AppState ⇄ Nook 同期
  IslandSurfaceDriving.swift  ( ~20行) — Kit 型を含まないプロトコル（fake 注入口）
  IslandChromeStyle.swift     ( ~40行) — notch/floating 2値 + Defaults 移行 + presentation マッピング
  ScreenLocator.swift         (~141行) — NookScreenLocator を Apache-2.0 のままコピー（帰属表示）
perch/Core/
  WidgetSizeMetrics.swift     ( ~25行) — [WidgetSize: CGFloat] の一本化先
perch/UI/
  IslandExpandedRoot.swift    ( ~30行) — expanded スロットの root
  IslandCompactSlots.swift    ( ~50行) — compactLeading / compactTrailing
```

### A-4. 表示モードと Defaults 移行

`NotchSimulationMode`（`.auto`/`.forceNotched`/`.forceNonNotched`）を廃し 2値に:

```swift
enum IslandChromeStyle: String, Codable, CaseIterable, Sendable {
    case notch      // 既定。ノッチ有無に関わらず疑似ノッチ（Atoll 風）
    case floating   // メニューバー下に浮かぶピル
}
```

- `.auto` は使わない（マシンで見た目が変わるのを避けるのが目的）
- 移行: `auto`/`forceNotched` → `.notch`、`forceNonNotched` → `.floating`。純粋関数 `IslandChromeStyle.migrating(fromLegacy:)` として実装しテストする
- `Nook.presentation` は `didSet` で `rebuildVisibleWindow` を呼ぶので実行中の切替がそのまま動く

### A-5. autoCollapseDelay の再現

```swift
nook.staysExpandedOnHoverExit = true
nook.$isHovering.sink { hovering in
    hovering ? cancelCollapse() : scheduleCollapse(after: Defaults[.autoCollapseDelay])
}
```

**挙動差**: 展開トリガに hover が加わる / 判定領域がウィンドウ矩形から `NookShape` の可視形状になる（改善）/ 「外側クリックで即収縮」は無くなる（hover 展開と喧嘩するため）/ グローバルイベント監視が不要になる（消費電力・入力監視の改善）。

### A-6. AppState の縮退

**`Nook.state` を single source of truth にし、`AppState.presentation` を一方向派生に降格。**

```
ユーザー操作 → AppState.expand(to:) → Task { await nook.expand() }
  → Nook.state → nook.onExpand/onCompact → AppState.applyNookState(_:) → SwiftUI
```

削除するもの:
- `transitionGeneration` — Kit の `runTransition` + `isCurrent(_:)` が同じことをしている
- `expand` の 110ms / `collapse` の 500ms タイマー — `await expand()` が settle まで待つ契約があるので二重に持つ意味がない
- `IslandPresentation` の `.expanding` / `.collapsing` — Kit から観測できず到達不能。`compact / expanded(IslandCard)` の2ケースに縮退
- `compactWindowSize` / `isPhysicalNotch` / `expandedWindowHeight` / `compactWindowWidth` / `compactWindowHeight` — 逆流とサイズ計算。すべて content-driven 化

`[WidgetSize: CGFloat]` の重複（`AppState.swift:34` と `ExpandedIslandView.swift:107`）は片方が消えるので、残る private let を `WidgetSizeMetrics` に切り出してテスト可能にする。

### A-7. `showInAllSpaces`

`NookPanel` は collectionBehavior を init で固定するので、`configureWindow` で毎回上書きする。**窓は expand/compact/presentation変更/画面変更のたびに作り直されるので、`onExpand`/`onCompact` の両方から `NookBridge.applyWindowChrome()` を呼ぶ**（PoC (d) で実証済み）。

### Phase A の差分見込み

削除 約1,530行（デッドコード 557 + Island層 641 + UIシェル層 ~200 + AppState ~130）、追加 約3,050行（vendored 2,617 + 新規 ~450）。**vendored を除いた自作コードは約 -1,080 行。**

### Phase A の完了判定

E-1 の手動チェックリスト全項目 + 新規ユニットテスト通過。

---

## Phase B — Atoll 風展開UI

ブランチ: `feat/expanded-ui-redesign`（Phase A マージ後）

### B-0. 設計方針 — Atoll から取るもの / 変えるもの

**必ず `/hallmark` と `/ui-ux-pro-max` を適用する。** Atoll の OSS 版は GPL-3.0 なのでソースは読まない。スクリーンショットから読み取れる**レイアウト構造の着想**のみを参考にし、視覚言語は Perch 独自にする。

| Atoll から引き継ぐ構造 | Perch での差別化 |
|---|---|
| 上部の横並びアイコンバーでモジュール切替 | アイコン選定・並び順・アクティブ表現を Perch の DesignSystem に合わせる。Perch は既に `PresetTabBar` を持つので**プリセット概念と統合**する（後述 B-1） |
| 右上のシステムステータス群 | Atoll は多数のグリフを並べる。Perch は**情報密度を落とし**、バッテリー + WiFi + BT の3点に絞る（hallmark の「情報を詰め込まない」原則） |
| NowPlaying: 左に大アートワーク、右にメタ情報 + シークバー + トランスポート | 既存の `NowPlayingCard.swift`(374) の資産を活かす。アートワーク内への波形オーバーレイは Perch の `ArtworkPalette` による色連動を強みにする |
| 右側の補助パネル（カレンダー / Mirror） | Perch は**ウィジェットシステムを既に持っている**ので、補助パネルは固定要素にせず `PresetLayout` の sidebar 配置として表現する |

### B-1. モジュール切替とプリセットの統合（設計判断）

Atoll の「ホーム / File Shelf / Timer」切替と、Perch の「Daily / Dev プリセット」は**別概念**。両方を上部バーに並べると混乱する。

**採用する構造**: 上部バーは **モジュール**（NowPlaying中心のホーム / File Shelf / Timer / AI Usage）。プリセットは**ホームモジュール内のウィジェット配置**として残す（現行の `PresetTabBar` はホームの中に置く、または Settings に退避）。

- `NookModule`（Kit の multi-module）は**使わない** — vendoring で NookKit を捨てたのに加え、descriptor.id の不変性制約とモジュール別 UserDefaults 分離を背負う実利がない
- モジュール切替は `@State selectedModule` + `PerchModule` enum で足りる
- `PresetStore` / `WidgetRegistry` / `WidgetProtocol` / `WidgetLayout` は**温存**（CLAUDE.md に「変更・削除禁止」と明記されている実装済みインフラ）

### B-2. 実装単位

| # | 内容 | 新規/改修 |
|---|---|---|
| 1 | `IslandTopBar` — 左にモジュールアイコン列、右にステータスクラスタ | 新規 ~120行 |
| 2 | `SystemStatusCluster` — バッテリー / WiFi / BT | 新規 ~150行 + 観測系 ~200行（B-3） |
| 3 | `PerchModule` enum + モジュールルーティング | 新規 ~60行 |
| 4 | NowPlaying 展開の再デザイン（`NowPlayingCard.swift` 改修） | 改修 ~200行 |
| 5 | `compactLeading` / `compactTrailing` のレジストリ駆動化（`pillPrimary`/`pillSecondary` を配線） | 改修 ~80行 |
| 6 | File Shelf モジュール — Shelf モデル4ファイル(607行、Apache-2.0)をコピー + `NookShelfView` は自作 | コピー607 + 新規 ~200行 |
| 7 | Timer モジュール | 新規 ~250行 |

### B-3. システムステータスの取得（Kit に部品は無い、全部自作）

| 項目 | API | 権限 |
|---|---|---|
| バッテリー | `IOPSCopyPowerSourcesInfo` → `IOPSCopyPowerSourcesList` → `IOPSGetPowerSourceDescription`（`kIOPSCurrentCapacityKey` 等）。通知は `IOPSNotificationCreateRunLoopSource` | **不要** |
| WiFi | `CWWiFiClient.shared().interface()` の `.powerOn()` / `.rssiValue()`。通知は `startMonitoringEvent(with:)` | **SSID を出さなければ不要**。`ssid()` は macOS 14+ で Location 権限が要り nil を返すので**表示しない設計にする** |
| Bluetooth | `IOBluetoothHostController.default()?.powerState` で ON/OFF のみ | **不要**（`CoreBluetooth` を使うと `NSBluetoothAlwaysUsageDescription` が必須になるので避ける） |

**権限ダイアログをゼロにする構成**を選ぶ。SSID 表示・接続デバイス名表示は要求しない。

### Phase B の完了判定

hallmark のチェックリスト通過 + 各モジュールが切り替わる + ステータスが実値を反映する + 権限ダイアログが1つも出ない。

---

## Phase C — 波形の実音キャプチャ修理

ブランチ: `fix/waveform-real-audio`（Phase B マージ後、または並行）

### C-1. 修理内容（原因は特定済み）

| # | 修正 | ファイル |
|---|---|---|
| 1 | **MediaRemote の bundleIdentifier を捨てずに伝搬する** — `NowPlayingState` に `sourceBundleId: String?` を追加し、`init?(fromMediaRemote:)` で `payload.bundleIdentifier` を保持。`NowPlayingManager` の `captureBundleId` はまずこれを見る | `NowPlayingState.swift:263-277`, `NowPlayingManager.swift:473-484` |
| 2 | **`ytmBrowserBundleId` の当てずっぽうを削除** — 1 が入れば不要になる。フォールバックとしてのみ残すか完全削除 | `NowPlayingManager.swift:415-419` |
| 3 | **`.mrMediaRemote` でもキャプチャする** — 1 で bundleId が取れるので `default: nil` を廃止 | `NowPlayingManager.swift:478` |
| 4 | **`SCStreamDelegate` を実装** — `stream(_:didStopWithError:)` で `currentBundleId = nil` にして再接続可能にする | `AudioCaptureService.swift:73` |
| 5 | **エラーを握りつぶさない** — `catch` に `logger.error`。`AudioPCMDecoder` の6種の `LocalizedError` を実際に出す | `AudioCaptureService.swift:132-138` |
| 6 | **再入ガード** — `startCapturing` を actor 化するか、`isStarting` フラグ + `currentBundleId` を開始時点で設定 | `AudioCaptureService.swift:33-35` |
| 7 | **権限の事前確認と拒否時UI** — `CGPreflightScreenCaptureAccess()` / `CGRequestScreenCaptureAccess()`。拒否時は Settings への導線を出す（`docs/progress.md:297` の `[ ] BF4`） | `AppDelegate.swift:38-45` |
| 8 | **診断モードを足す** — Settings に「波形が実音か合成かを表示する」デバッグ表示。**再発を即座に検知できるようにする**（今回の再発の根本原因は「壊れても見た目が同じ」だったこと） | `SettingsView.swift` |
| 9 | **テストを書く** — `AudioPCMDecoder`（各フォーマットのデコード）、`AudioSpectrumAnalyzer`（既知の入力に対するバンド出力）、`WaveformView.blendedLevels`（実音/合成/無音の3分岐）。いずれも純粋関数に近い | 新規 `perchTests/NowPlaying/Audio*Tests.swift` |

### C-2. 切り分け手順（実装の最初にやる）

1. `AudioCaptureService.swift:132-138` の `catch` にログを入れて実行 → デコード失敗かバッファ未到達かを切り分け
2. `:38` の `SCShareableContent` 直後に `content.applications.count` をログ → 0 なら TCC 権限問題で確定
3. **Spotify で試す** — Spotify/Apple Music は bundleId が正しいので、これで動くなら YTM のブラウザ誤選択が犯人と確定。最も切り分け効率が高い

### C-3. 将来（別PR）— Core Audio Taps への載せ替え

Phase C で SCK が直っても、**macOS 15 のオレンジインジケータ常時点灯と定期再認証は残る**。常駐アプリとして痛いので、別PRで CATap に載せ替える。見積 8〜11人日。

実装の必須ルール（コミュニティで頻出する罠）:
- `isExclusive` は初期化子の意味論のまま**触らない**（触ると無音になる）
- アグリゲートは「実出力デバイス = main sub-device、tap = sub-tap、`kAudioAggregateDeviceTapAutoStartKey: true`」（構造ミスでエラーなしのゼロサンプル）
- `AVAudioEngine` は**使わない**。`AudioDeviceCreateIOProcIDWithBlock` を直接（retarget が `noErr` を返すのに既定入力を読み続ける）
- IOProc の queue に `nil` を渡さない（macOS 26 でサイレント失敗）
- **プロセス指定ではなくグローバルタップ**（Teams 等で無音になる報告あり）
- **署名なしビルドでは TCC ダイアログがそもそも出ない**
- macOS 26 に「長時間稼働で全サンプルが 0 になる」未解決OSバグ（Apple Forums #825780、Apple 未回答）→ 連続ゼロを検知してタップ+アグリゲートを両方破棄して再作成するウォッチドッグ必須

参照元は **AudioCap(BSD-2)** と **iqualize(MIT)** のみ。boring.notch / Atoll は GPL-3.0 なので読まない。

---

## 横断事項

### ライセンス

Perch は Apache-2.0。vendoring で以下の義務が発生する。

- `perch/Vendor/NookSurface/` の各ファイルの SPDX ヘッダを保持（MIT / Glendon Chin、原著 DynamicNotchKit / Kai Azim）
- `ThirdPartyLicenses/NookSurface-MIT.txt`, `ThirdPartyLicenses/DynamicNotchKit-MIT.txt`, `ThirdPartyLicenses/OpenNook-Apache-2.0.txt`（ScreenLocator / Shelf モデルをコピーする分）
- ルートの `NOTICE` に帰属を記載
- **アプリ内 Acknowledgements**（Settings に「About / Licenses」）— Apache-2.0 §4(d)
- `release.yml` の DMG 生成に `ThirdPartyLicenses/` を同梱

### macOS 15 引き上げ

`project.pbxproj` の `MACOSX_DEPLOYMENT_TARGET = 14.0` → `15.0`（**4箇所前後、grep で全数確認**）、`CLAUDE.md` の Tech Stack、`README.md`、Homebrew Cask の `depends_on macos: ">= :sequoia"`。CI は `macos-26` ランナーなので変更不要。**Sparkle 未導入の今が最も傷が浅い。**

### CLAUDE.md の更新（Phase A で実施）

- Tech Stack: `macOS 14 Sonoma+` → `macOS 15 Sequoia+`
- Architecture 図の `Integration Layer (AppKit)` → `NookBridge — vendored NookSurface のアダプタ`
- Dependencies 表から `KeyboardShortcuts` を削除、`Vendored: NookSurface 0.4.0 (MIT)` を追記
- Phase Roadmap を書き換え:

```diff
-| 4 | v0.4 | File Shelf（D&D、一時保存、Quick Look、AirDrop） |
-| 5 | v0.5 | Dev Status（GitHub Actions、CI通知） |
-| 6 | v1.0 | Sparkle、Homebrew Cask、追加Provider、HUD、安定化 |
+| 3.5 | v0.35 | Phase A: Island 層を vendored NookSurface に置換 |
+| 3.6 | v0.36 | Phase B: Atoll 風展開UI（モジュールバー、システムステータス、NowPlaying 再デザイン、File Shelf、Timer） |
+| 3.7 | v0.37 | Phase C: 波形の実音キャプチャ修理（SCK）+ テスト整備 |
+| 4 | v0.4 | 波形を Core Audio Taps へ載せ替え（オレンジインジケータ解消） |
+| 5 | v0.5 | Dev Status（GitHub Actions、CI通知） |
+| 6 | v1.0 | Sparkle、Homebrew Cask、追加Provider、輝度HUD、安定化 |
```

- Skills の `appkit-window-control` は「vendored NookSurface の改変指針」に書き換え

### テスト戦略

CLAUDE.md の「タスクごとに必ずテストコードを追加」を満たす。UI 置換で失われるテストを純粋関数の抽出で補填する。

**新規**:
- `IslandChromeStyleTests` — `nookPresentation` の2ケース、`migrating(fromLegacy:)` の5ケース全網羅
- `WidgetSizeMetricsTests` — `AppStateTests` の `expandedWindowHeight` 検証を移植
- `NookBridgeTests` — `collapseDelay` / `desiredCollectionBehavior` / `makeBackdrop`（すべて純粋関数）
- `Audio*Tests`（Phase C）— デコーダ・解析器・`blendedLevels` の3分岐

**改廃**:
- `IslandGeometryTests`(149) → **全削除**（`IslandGeometry` が消える）
- `NotchDetectorTests`(136) → **全削除**（`.auto` を使わないので `hasNotch` 判定が不要）
- `AppStateTests`(82) → サイズ検証を移植、遷移テストは `IslandSurfaceDriving` の fake 注入に書き換え
- `IslandPresentationTests`(70) → `.expanding`/`.collapsing` のケースを削除
- `PresetStore` / `WidgetLayout` / `WidgetRegistry` / `WidgetSize` / `AIUsage` / `NowPlaying` / `Providers` → **無変更**

`IslandSurfaceDriving` プロトコル（Kit 型を含まない）を切って `FakeIslandSurface` を注入できるようにするのが、vendoring 依存を局所化する設計とテスト容易性を同時に満たす。

---

## E-1. 手動リグレッションチェックリスト（Phase A の PR 本文に貼る）

`perchUITests/` は Xcode テンプレートのまま実質空で、UI リグレッションは手動でしか検出できない。全項目にチェックが付くまでマージしない。

```markdown
### 表示
- [ ] 起動直後に compact が表示される
- [ ] 疑似ノッチが実ノッチ相当の幅（195pt前後）で描かれる
- [ ] 音楽再生中: compactLeading にアートワーク + 波形 / AI 使用量あり: compactTrailing にグリフ
- [ ] 音楽停止中: compact が薄くなる
- [ ] Settings > Island Style を「浮かべるピル」に切り替えると再起動なしで形が変わる

### インタラクション
- [ ] hover で展開する（新挙動）/ タップでも展開する
- [ ] 展開中に PresetTabBar で Daily ⇄ Dev を切替でき、高さがプリセットに応じて変わる
- [ ] hover を外して autoCollapseDelay 秒後に閉じる
- [ ] メニューバーの Perch アイコン > Settings… で設定が開く

### クリック透過（最重要）
- [ ] 画面上半分の Finder アイコンをクリックできる
- [ ] メニューバーのシステムメニューが開ける
- [ ] Spotlight / Mission Control が起動する
- [ ] 他アプリのウィンドウをドラッグできる

### マルチディスプレイ / Space
- [ ] 外部ディスプレイを抜き差しして再配置される
- [ ] Space を切り替えて追従する / showInAllSpaces = false で追従しなくなる
- [ ] 他アプリをフルスクリーンにしても Perch が消えない

### 常駐品質
- [ ] 30分放置後の CPU < 0.5%、メモリ増分 < 30MB
- [ ] 展開⇄収縮を20回連続で往復してもレースで壊れない
- [ ] トラック切替（アートワーク変更）中に展開してもレイアウトが崩れない

### Defaults 移行
- [ ] 旧 notchSimulationMode = forceNonNotched → floating に移行される
- [ ] 旧 auto / forceNotched → notch に移行される
```

---

## Critical Files

| パス | 役割 |
|---|---|
| `perch/Island/IslandWindowController.swift`(243) | 削除 → `NookBridge.swift` へ縮退。全回避策の集約点 |
| `perch/Core/AppState.swift` | 6プロパティ削除、タイマー/generation 削除、`applyNookState(_:)` 追加 |
| `perch/UI/RootIslandView.swift` | 2分岐と `currentTapShape` を削除し、compact/expanded を3スロットへ分解する起点 |
| `perch/UI/ExpandedIslandView.swift` | `widgetView(for:)` が唯一の実レンダリング地点。glass/shape/固定幅を剥がす |
| `perch/UI/SettingsView.swift` | Island Style を2択化、pillSize / animationSpeed を削除、Phase C で診断表示追加 |
| `perch/Features/NowPlaying/NowPlayingState.swift`(279) | Phase C: `sourceBundleId` を追加して MediaRemote の情報を捨てない |
| `perch/Features/NowPlaying/AudioCaptureService.swift`(155) | Phase C: delegate 実装、エラーログ、再入ガード |
| `perch.xcodeproj/project.pbxproj` | macOS 15、vendored ファイル追加、KeyboardShortcuts 削除、`LiquidBlob.metal` 削除 |
| `CLAUDE.md` | macOS 15、Architecture 図、Phase Roadmap、Dependencies |

---

## Verification

```bash
xcodebuild -scheme perch -configuration Debug build
xcodebuild -scheme perch -configuration Debug test
swift-format lint --recursive perch/ perchTests/    # perch/Vendor/ は除外設定を追加
open perch.xcodeproj    # Run して E-1 のチェックリストを全通し
```

- 各コミット後に build + test。Phase A の本体コミット後は E-1 の全項目を手動確認
- Phase C は「Spotify で実音が動くこと」を最初の判定基準にする（切り分け効率が最も高い）
- push 後は `/ci-monitoring` で CI を確認
- PR はフェーズ単位。Claude 自身をレビュワーにアサイン。スカッシュマージは使わない
