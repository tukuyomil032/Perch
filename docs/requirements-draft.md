ごめん、前の出し方が悪かった。
下に**1つのMarkdownファイルとしてそのままコピーできる形**でまとめ直す。

````markdown
# Perch 技術構成・機能設計メモ

## 0. コンセプト

Perchは、macOSの画面上端中央に常駐する「Dynamic Island風ライブハブ」アプリ。

物理ノッチがあるMacBookではノッチ周辺に自然に馴染ませ、ノッチがないMacではiPhoneのDynamic Islandに近いピル型UIとして表示する。

主目的は、単なるノッチ装飾ではなく、以下の情報や操作を小さく・美しく・常時アクセス可能にすること。

- AI利用状況
- Claude Code / Codex / GitHub Actionsなどの開発ステータス
- Now Playing
- ファイル一時棚
- AirDrop / Quick Look
- 小型HUD
- Raycast風のクイックアクション
- 将来的な拡張機能

---

## 1. 参考元プロジェクトの役割整理

### 1.1 Boring Notch

参考元:

- https://github.com/TheBoredTeam/boring.notch

参考にする部分:

- Dynamic Island風の展開UI
- Now Playing
- 音楽コントロール
- カレンダー
- リマインダー
- ファイル棚
- AirDrop
- macOS HUD置き換え
- 拡張システム構想

Perchでは、Boring Notchをそのまま真似するのではなく、以下の思想を取り込む。

- ピルが通常時は小さく、イベント発生時に展開する
- 複数機能をカードとして切り替える
- 音楽・ファイル・HUD・開発状態を同じライブハブに統合する
- macOS標準UIより気持ちいい操作感を目指す

---

### 1.2 NotchDrop

参考元:

- https://github.com/Lakr233/NotchDrop

参考にする部分:

- 透明な上端オーバーレイウィンドウ
- ノッチ検出
- ノッチなし環境でのfallbackサイズ
- ファイルドロップ
- AirDrop起動
- 一時保存
- Quick Look的なファイル操作

NotchDropは、MacBookのノッチをファイルドロップゾーンにするアプリ。

Perchでは、NotchDropの以下の設計を参考にする。

- `NSWindow`を透明・枠なしにする
- `.canJoinAllSpaces`で全Spacesに表示する
- `.fullScreenAuxiliary`でフルスクリーン補助ウィンドウにする
- `level = .statusBar + n`で上端に常駐させる
- `NSScreen.safeAreaInsets.top`でノッチ有無を判定する
- ノッチがない場合はピル型fallbackを使う
- ドラッグ&ドロップをファイル棚に接続する

---

### 1.3 CodexBar

参考元:

- https://github.com/steipete/CodexBar

参考にする部分:

- AI利用状況の取得
- ProviderごとのCore分離
- バックグラウンド更新ループ
- CLIとの分離
- 設定管理
- Provider状態のUI表示
- Sparkleによる更新
- KeyboardShortcuts
- privacy-firstなローカル処理

CodexBarは、AI coding providerの使用量、残量、リセット時間、ステータスなどをメニューバーで確認できるアプリ。

Perchでは、CodexBarの「AI使用量監視」部分をDynamic Island UIに再構成する。

参考にする設計:

```text
Sources/CodexBarCore:
  fetch / parse / provider logic

Sources/CodexBar:
  state / UI / menu bar app

Sources/CodexBarCLI:
  CLI output

Widget / helper:
  将来的な拡張
```

Perchでも、UIとデータ取得を強く分離する。

---

## 2. アプリ全体の方向性

Perchは、次の3層で構成する。

```text
UI Layer
  - Dynamic Island風ピル
  - 展開カード
  - 設定画面
  - メニューバーアイコン

Core Layer
  - 状態管理
  - Provider更新ループ
  - 通知キュー
  - ファイル棚管理
  - Now Playing管理

Integration Layer
  - Claude / Codex / OpenAI / OpenRouter
  - GitHub
  - macOS Media
  - File System
  - AirDrop
  - Shell / CLI
```

設計上の重要ポイント:

- UIとデータ取得を分ける
- Providerはプラグイン的に追加できるようにする
- ノッチあり/なしを同列に扱う
- ノッチなしMacをfallback扱いにしない
- macOSアプリとして自然に振る舞う
- 最初から全部入りにしない
- MVPでは「ピルUI + Now Playing + AI使用量 + ファイル棚」までを目標にする

---

## 3. 使用言語・技術構成

### 3.1 メイン言語

```text
Swift
```

理由:

- macOSネイティブAPIに直接アクセスできる
- AppKitとSwiftUIを自然に混ぜられる
- 透明オーバーレイ、window level、Spaces対応がやりやすい
- Menu Bar App、Login Item、Sparkle、KeyboardShortcutsとの相性が良い
- Objective-C++を使わなくてもMVPは十分実装可能

---

### 3.2 UI

```text
SwiftUI + AppKit
```

役割:

```text
SwiftUI:
  - ピル本体
  - 展開カード
  - アニメーション
  - 設定画面
  - Providerカード

AppKit:
  - NSWindow / NSPanel制御
  - 透明ウィンドウ
  - 最前面制御
  - 全Spaces表示
  - フルスクリーン補助
  - マウスイベント制御
  - メニューバー常駐
```

SwiftUIだけで完結させるのは避ける。

理由は、Perchの核である「画面上端中央に常駐する透明ウィンドウ」はAppKit側の制御が必要になるため。

---

### 3.3 Objective-C++の扱い

MVPでは使わない。

使う可能性があるのは、以下のような高度な機能を入れる段階。

```text
- private frameworkを使ったNow Playing制御
- SkyLight/CoreGraphics系の深いウィンドウ制御
- macOS標準HUDの本格置き換え
- C/C++ライブラリとの接続
- 低レベルなイベント監視
```

最初からObjective-C++を混ぜると、ビルド構成、署名、保守性が重くなるため、まずはSwift中心で進める。

---

## 4. 最小対応環境

```text
macOS 14 Sonoma+
Apple Silicon / Intel 両対応
Xcode 16+
Swift 6系
```

---

## 5. 依存関係候補

### 5.1 MVPで入れてよい依存

```swift
.package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.4.0")
.package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.1")
.package(url: "https://github.com/sindresorhus/Defaults", from: "9.0.0")
.package(url: "https://github.com/apple/swift-log", from: "1.12.0")
```

用途:

| 依存 | 用途 |
|---|---|
| KeyboardShortcuts | グローバルショートカット |
| Sparkle | 自動アップデート |
| Defaults | 設定保存を型安全に扱う |
| swift-log | ログ基盤 |

---

### 5.2 後回しでよい依存

```swift
.package(url: "https://github.com/airbnb/lottie-spm.git", from: "4.5.0")
.package(url: "https://github.com/EmergeTools/Pow", from: "1.0.0")
.package(url: "https://github.com/ChimeHQ/AsyncXPCConnection", from: "1.3.0")
```

用途:

| 依存 | 用途 |
|---|---|
| Lottie | リッチなアニメーション |
| Pow | SwiftUIの追加アニメーション |
| AsyncXPCConnection | helper process連携 |
| SkyLightWindow系 | 高度なwindow制御 |

最初から入れすぎない。

特にXPCやSkyLight系は、必要になってからでよい。

---

## 6. 機能一覧

### 6.1 Core UI

| 機能 | 優先度 | 説明 |
|---|---:|---|
| ピル型Dynamic Island UI | S | アプリの中心 |
| ノッチあり/なし判定 | S | 表示モード切り替え |
| hover展開 | S | iPhone的な体験 |
| click展開 | S | 操作の入口 |
| 自動収納 | S | 邪魔にならない |
| 複数カード切り替え | A | AI、音楽、ファイルなど |
| 外部ディスプレイ対応 | A | ノッチなし画面でも表示 |
| 表示位置調整 | B | 中央/上端余白など |
| アニメーション設定 | B | 好みに応じて速度変更 |

---

### 6.2 AI Usage

| 機能 | 優先度 | 説明 |
|---|---:|---|
| Claude使用量 | S | Claude Code/Claude API/Session |
| Codex使用量 | S | CodexBar系の主機能 |
| OpenAI使用量 | A | API/ChatGPT系 |
| OpenRouter残高 | A | APIユーザー向け |
| Cursor利用状況 | B | 開発者向け |
| Copilot利用状況 | B | GitHub連携 |
| Provider別カード | S | 展開時に詳細表示 |
| リセット時刻 | S | 残り時間表示 |
| エラー表示 | A | 認証切れ/取得失敗 |
| 更新間隔設定 | A | 1分/5分/15分/手動 |

表示例:

```text
Compact:
  Claude 72%

Expanded:
  Claude
  Session: 72% remaining
  Weekly: 41% remaining
  Reset in: 2h 14m

  Codex
  Usage: 38%
  Review left: 12
```

---

### 6.3 Dev Status

| 機能 | 優先度 | 説明 |
|---|---:|---|
| GitHub Actions状態 | A | success/failure/running |
| PR状態 | B | review required/merged |
| Issue通知 | C | 後回し |
| ローカルgit状態 | B | branch/dirty/build |
| Claude Code実行状態 | A | running/waiting/failed |
| Codex CLI実行状態 | A | running/waiting/failed |
| CI失敗通知 | A | ピル展開で知らせる |

表示例:

```text
Compact:
  Build failed

Expanded:
  MC-Vector
  E2E macOS failed
  Windows passed
  Ubuntu passed
```

---

### 6.4 Now Playing

| 機能 | 優先度 | 説明 |
|---|---:|---|
| 曲名表示 | S | Dynamic Island感が強い |
| アーティスト表示 | S | 基本情報 |
| アルバムアート | A | 展開時に表示 |
| 再生/停止 | A | 操作可能にする |
| 次へ/前へ | A | 操作可能にする |
| 音量表示 | B | HUDと連携 |
| ビジュアライザー | C | 後回し |

#### 検出方式（macOS 16 対応）

macOS 15.4+ で MRMediaRemote がエンタイトルメント制限でブロックされるため、マルチソース検出を採用する。

| ソース | アプリ | 方式 |
|--------|--------|------|
| DistributedNotificationCenter | Spotify | `com.spotify.client.PlaybackStateChanged` |
| DistributedNotificationCenter | Apple Music | `com.apple.Music.playerInfo` |
| AppleScript ポーリング（3秒） | YouTube Music | Chrome ウィンドウタイトル解析 |
| MRMediaRemote（fallback） | 任意 | macOS < 15.4 のみ有効 |

#### 必要エンタイトルメント

Apple Events 一時例外（sandbox 無効のため実質不要だが明示的に記載）:
- `com.apple.security.automation.apple-events`
- `com.spotify.client`, `com.apple.Music`, `com.google.Chrome`

アートワーク取得はフェーズ後半に AppleScript/Spotify API 経由で実装予定。
YouTube Music の一時停止検出はタイトル変化なしのため後続フェーズで対応。

---

### 6.5 File Shelf

| 機能 | 優先度 | 説明 |
|---|---:|---|
| ファイルドロップ | S | NotchDrop由来 |
| 一時保存 | S | Perch内に保持 |
| クリックで開く | S | 基本操作 |
| Quick Look | A | 便利 |
| AirDrop起動 | A | NotchDrop系 |
| 自動削除 | A | 1日後など |
| Option+削除 | B | 操作性 |
| 複数ファイル表示 | A | 展開カード内で表示 |

---

### 6.6 Quick HUD / Launcher

| 機能 | 優先度 | 説明 |
|---|---:|---|
| グローバルショートカット | S | Perchを開く |
| Raycast風クイックアクション | B | 後半 |
| Clipboard表示 | B | 小型履歴 |
| タイマー | C | 後回し |
| ショートカット実行 | B | macOS Shortcuts連携 |
| コマンド実行 | B | 開発者向け |

---

### 6.7 System HUD

| 機能 | 優先度 | 説明 |
|---|---:|---|
| 音量HUD | B | かっこいいが難しい |
| 明るさHUD | B | 後回し |
| キーボードバックライト | C | 後回し |
| バッテリー表示 | B | 低難度 |
| 充電開始通知 | B | Dynamic Island感あり |

---

## 7. プロジェクト構成案

Swift Package中心の構成にする。

```text
Perch/
  Package.swift
  README.md
  LICENSE
  .github/
    workflows/
      build.yml
      release.yml

  Sources/
    PerchApp/
      PerchApp.swift
      AppDelegate.swift
      MenuBarController.swift
      SettingsScene.swift

    PerchCore/
      AppState.swift
      EventBus.swift
      Logger.swift
      RefreshScheduler.swift
      Preferences.swift

    PerchIsland/
      IslandWindow.swift
      IslandWindowController.swift
      IslandMode.swift
      IslandGeometry.swift
      NotchDetector.swift
      MouseEventMonitor.swift

    PerchUI/
      RootIslandView.swift
      CompactPillView.swift
      ExpandedIslandView.swift
      IslandCardContainer.swift
      ProviderUsageCard.swift
      NowPlayingCard.swift
      FileShelfCard.swift
      DevStatusCard.swift
      SettingsView.swift

    PerchFeatures/
      NowPlaying/
        NowPlayingManager.swift
        NowPlayingState.swift
        MediaCommand.swift

      FileShelf/
        ShelfItem.swift
        ShelfStore.swift
        ShelfDropHandler.swift
        TemporaryFileStorage.swift
        QuickLookService.swift
        AirDropService.swift

      AIUsage/
        AIProvider.swift
        AIUsageSnapshot.swift
        AIUsageStore.swift
        AIRefreshService.swift

      DevStatus/
        GitHubActionsProvider.swift
        LocalGitProvider.swift
        ProcessWatcher.swift

      HUD/
        HUDState.swift
        VolumeHUDProvider.swift
        BatteryProvider.swift

    PerchProviders/
      Claude/
        ClaudeProvider.swift
        ClaudeCredentials.swift
        ClaudeUsageParser.swift

      Codex/
        CodexProvider.swift
        CodexConfigReader.swift
        CodexUsageParser.swift

      OpenAI/
        OpenAIProvider.swift
        OpenAIAPIClient.swift

      OpenRouter/
        OpenRouterProvider.swift
        OpenRouterAPIClient.swift

      GitHub/
        GitHubClient.swift
        GitHubActionsClient.swift

    PerchCLI/
      main.swift
      Commands/
        StatusCommand.swift
        ProvidersCommand.swift
        RefreshCommand.swift

  Tests/
    PerchCoreTests/
    PerchProviderTests/
    PerchUITests/
```

---

## 8. モジュール責務

### 8.1 PerchApp

アプリの起動・メニューバー・設定画面・AppDelegateを担当。

```text
責務:
  - アプリ起動
  - LSUIElement appとしてDock非表示
  - Menu Bar icon表示
  - Settings window表示
  - Sparkle updater
  - Login item
```

---

### 8.2 PerchIsland

画面上端ピルウィンドウの制御を担当。

```text
責務:
  - ノッチ検出
  - ノッチあり/なしモード決定
  - NSWindow/NSPanel生成
  - frame計算
  - Spaces対応
  - fullscreen対応
  - hover/click判定
  - 表示/非表示
```

---

### 8.3 PerchUI

SwiftUIによる表示部分。

```text
責務:
  - compact pill
  - expanded island
  - card layout
  - animation
  - provider cards
  - settings UI
```

---

### 8.4 PerchCore

共通状態管理。

```text
責務:
  - AppState
  - EventBus
  - Preferences
  - RefreshScheduler
  - Logging
  - Notification queue
```

---

### 8.5 PerchFeatures

機能単位の実装。

```text
責務:
  - Now Playing
  - File Shelf
  - AI Usage
  - Dev Status
  - HUD
```

---

### 8.6 PerchProviders

外部サービス別の実装。

```text
責務:
  - Claude
  - Codex
  - OpenAI
  - OpenRouter
  - GitHub
  - Cursor
  - Copilot
```

---

## 9. 動作フロー

### 9.1 アプリ起動時

```text
1. PerchApp起動
2. AppDelegate初期化
3. Preferences読み込み
4. Provider設定読み込み
5. NSScreen情報取得
6. ノッチあり/なし判定
7. IslandWindow生成
8. CompactPillView表示
9. RefreshScheduler開始
10. MenuBarController開始
```

---

### 9.2 ノッチ判定フロー

```text
1. NSScreen.mainを取得
2. safeAreaInsets.topを確認
3. auxiliaryTopLeftArea / auxiliaryTopRightAreaを確認
4. ノッチ幅を計算
5. notchSizeが.zeroならfloatingPill
6. notchSizeが存在すればphysicalNotch
7. IslandGeometryに反映
```

---

### 9.3 UI展開フロー

```text
1. mouse hover or click
2. AppState.isExpanded = true
3. CompactPillView → ExpandedIslandView
4. 現在優先度が高いcardを表示
5. 一定時間操作がなければcompactへ戻る
```

優先度例:

```text
1. エラー/警告
2. 現在実行中の開発タスク
3. Now Playing
4. AI使用量
5. File Shelf
6. Idle
```

---

### 9.4 AI使用量更新フロー

```text
1. RefreshSchedulerが一定間隔でtick
2. enabled providersを取得
3. 各AIProvider.refresh()を並列実行
4. AIUsageSnapshotを生成
5. AIUsageStoreに保存
6. AppStateに反映
7. UIが自動更新
8. エラー時はProviderErrorとして保持
```

---

### 9.5 ファイルドロップフロー

```text
1. ユーザーがファイルを上端ピルにドラッグ
2. Drag hover検知
3. PerchがFileShelfCardを展開
4. Drop受け取り
5. security scoped bookmark作成
6. temporary storageにコピーまたは参照保存
7. ShelfItem生成
8. UI更新
9. 一定期間後に自動削除
```

---

### 9.6 GitHub Actions監視フロー

```text
1. GitHubProviderが対象repoを取得
2. 最新workflow runを取得
3. running / success / failureを判定
4. 失敗時はPerchEventを発行
5. ピルに短時間表示
6. 展開時に詳細表示
```

---

## 10. コード例

### 10.1 ノッチ検出

```swift
import AppKit

extension NSScreen {
    var perchNotchSize: CGSize {
        guard safeAreaInsets.top > 0 else {
            return .zero
        }

        let notchHeight = safeAreaInsets.top
        let fullWidth = frame.width
        let leftAreaWidth = auxiliaryTopLeftArea?.width ?? 0
        let rightAreaWidth = auxiliaryTopRightArea?.width ?? 0

        guard leftAreaWidth > 0, rightAreaWidth > 0 else {
            return .zero
        }

        let notchWidth = fullWidth - leftAreaWidth - rightAreaWidth

        guard notchWidth > 0 else {
            return .zero
        }

        return CGSize(width: notchWidth, height: notchHeight)
    }

    var isBuiltInDisplay: Bool {
        let key = NSDeviceDescriptionKey(rawValue: "NSScreenNumber")

        guard
            let value = deviceDescription[key] as? NSNumber
        else {
            return false
        }

        return CGDisplayIsBuiltin(value.uint32Value) == 1
    }
}
```

---

### 10.2 Island Mode

```swift
import Foundation

enum IslandMode: Equatable {
    case physicalNotch
    case floatingPill
}

struct IslandConfiguration: Equatable {
    var mode: IslandMode
    var compactSize: CGSize
    var expandedSize: CGSize
    var topOffset: CGFloat
}
```

---

### 10.3 Geometry計算

```swift
import AppKit

struct IslandGeometry {
    static func configuration(for screen: NSScreen) -> IslandConfiguration {
        let notchSize = screen.perchNotchSize

        if notchSize == .zero {
            return IslandConfiguration(
                mode: .floatingPill,
                compactSize: CGSize(width: 150, height: 34),
                expandedSize: CGSize(width: 420, height: 180),
                topOffset: 8
            )
        }

        return IslandConfiguration(
            mode: .physicalNotch,
            compactSize: CGSize(
                width: max(notchSize.width, 150),
                height: max(notchSize.height, 32)
            ),
            expandedSize: CGSize(width: 460, height: 190),
            topOffset: 0
        )
    }

    static func compactFrame(
        screen: NSScreen,
        configuration: IslandConfiguration
    ) -> CGRect {
        let size = configuration.compactSize

        return CGRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height - configuration.topOffset,
            width: size.width,
            height: size.height
        )
    }

    static func expandedFrame(
        screen: NSScreen,
        configuration: IslandConfiguration
    ) -> CGRect {
        let size = configuration.expandedSize

        return CGRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height - configuration.topOffset,
            width: size.width,
            height: size.height
        )
    }
}
```

---

### 10.4 透明オーバーレイウィンドウ

```swift
import AppKit

final class IslandWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false,
            screen: screen
        )

        isOpaque = false
        backgroundColor = .clear
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovable = false
        hasShadow = false

        collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle
        ]

        level = .statusBar + 8
    }

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}
```

---

### 10.5 Window Controller

```swift
import AppKit
import SwiftUI

@MainActor
final class IslandWindowController: NSWindowController {
    private let appState: AppState
    private let screen: NSScreen
    private var configuration: IslandConfiguration

    init(screen: NSScreen, appState: AppState) {
        self.screen = screen
        self.appState = appState
        self.configuration = IslandGeometry.configuration(for: screen)

        let window = IslandWindow(screen: screen)

        super.init(window: window)

        let rootView = RootIslandView()
            .environment(appState)

        contentViewController = NSHostingController(rootView: rootView)

        window.setFrame(
            IslandGeometry.compactFrame(
                screen: screen,
                configuration: configuration
            ),
            display: true
        )

        window.makeKeyAndOrderFront(nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    func updateExpandedState(_ expanded: Bool) {
        guard let window else {
            return
        }

        let frame = expanded
            ? IslandGeometry.expandedFrame(screen: screen, configuration: configuration)
            : IslandGeometry.compactFrame(screen: screen, configuration: configuration)

        window.animator().setFrame(frame, display: true)
    }
}
```

---

### 10.6 AppState

```swift
import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    var isExpanded = false
    var activeCard: IslandCard = .idle
    var aiSnapshots: [AIUsageSnapshot] = []
    var nowPlaying: NowPlayingState?
    var shelfItems: [ShelfItem] = []
    var devStatuses: [DevStatus] = []
    var latestError: PerchError?
}
```

---

### 10.7 Card種別

```swift
enum IslandCard: String, CaseIterable, Identifiable {
    case idle
    case aiUsage
    case nowPlaying
    case fileShelf
    case devStatus
    case hud

    var id: String {
        rawValue
    }
}
```

---

### 10.8 Compact Pill View

```swift
import SwiftUI

struct CompactPillView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 8) {
            indicator

            if let label = compactLabel {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(.black)
        .foregroundStyle(.white)
        .clipShape(Capsule())
        .onHover { hovering in
            if hovering {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    appState.isExpanded = true
                }
            }
        }
    }

    private var indicator: some View {
        Circle()
            .frame(width: 6, height: 6)
            .opacity(0.85)
    }

    private var compactLabel: String? {
        switch appState.activeCard {
        case .aiUsage:
            return appState.aiSnapshots.first?.compactTitle
        case .nowPlaying:
            return appState.nowPlaying?.title
        case .devStatus:
            return appState.devStatuses.first?.title
        case .fileShelf:
            return "\(appState.shelfItems.count) files"
        case .hud:
            return "HUD"
        case .idle:
            return nil
        }
    }
}
```

---

### 10.9 Expanded Island View

```swift
import SwiftUI

struct ExpandedIslandView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 12) {
            header

            switch appState.activeCard {
            case .aiUsage:
                AIUsageCard()
            case .nowPlaying:
                NowPlayingCard()
            case .fileShelf:
                FileShelfCard()
            case .devStatus:
                DevStatusCard()
            case .hud:
                HUDCard()
            case .idle:
                IdleCard()
            }
        }
        .padding(16)
        .frame(width: 420)
        .background(.black)
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .onHover { hovering in
            if !hovering {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    appState.isExpanded = false
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Perch")
                .font(.system(size: 13, weight: .bold))

            Spacer()

            Text(appState.activeCard.rawValue)
                .font(.system(size: 11, weight: .medium))
                .opacity(0.6)
        }
    }
}
```

---

### 10.10 Root View

```swift
import SwiftUI

struct RootIslandView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack(alignment: .top) {
            if appState.isExpanded {
                ExpandedIslandView()
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            } else {
                CompactPillView()
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: appState.isExpanded)
    }
}
```

---

### 10.11 AI Provider Protocol

```swift
import Foundation

protocol AIProvider: Sendable {
    var id: String { get }
    var displayName: String { get }

    func refresh() async throws -> AIUsageSnapshot
}
```

---

### 10.12 AI Usage Snapshot

```swift
import Foundation

struct AIUsageSnapshot: Identifiable, Sendable, Equatable {
    var id: String
    var providerName: String
    var primaryWindow: UsageWindow?
    var secondaryWindow: UsageWindow?
    var lastUpdated: Date
    var status: ProviderStatus

    var compactTitle: String {
        if let percent = primaryWindow?.percentRemaining {
            return "\(providerName) \(Int(percent * 100))%"
        }

        return providerName
    }
}

struct UsageWindow: Sendable, Equatable {
    var label: String
    var percentRemaining: Double?
    var resetDate: Date?
    var used: Double?
    var limit: Double?
}

enum ProviderStatus: Sendable, Equatable {
    case ok
    case stale
    case error(String)
}
```

---

### 10.13 AI Usage Store

```swift
import Foundation
import Observation

@MainActor
@Observable
final class AIUsageStore {
    private(set) var snapshots: [AIUsageSnapshot] = []
    private let providers: [AIProvider]

    init(providers: [AIProvider]) {
        self.providers = providers
    }

    func refreshAll() async {
        await withTaskGroup(of: AIUsageSnapshot?.self) { group in
            for provider in providers {
                group.addTask {
                    do {
                        return try await provider.refresh()
                    } catch {
                        return AIUsageSnapshot(
                            id: provider.id,
                            providerName: provider.displayName,
                            primaryWindow: nil,
                            secondaryWindow: nil,
                            lastUpdated: Date(),
                            status: .error(error.localizedDescription)
                        )
                    }
                }
            }

            var nextSnapshots: [AIUsageSnapshot] = []

            for await snapshot in group {
                if let snapshot {
                    nextSnapshots.append(snapshot)
                }
            }

            snapshots = nextSnapshots.sorted { $0.providerName < $1.providerName }
        }
    }
}
```

---

### 10.14 Refresh Scheduler

```swift
import Foundation

actor RefreshScheduler {
    private var task: Task<Void, Never>?

    func start(
        interval: Duration,
        operation: @escaping @Sendable () async -> Void
    ) {
        task?.cancel()

        task = Task {
            while !Task.isCancelled {
                await operation()

                do {
                    try await Task.sleep(for: interval)
                } catch {
                    break
                }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
```

---

### 10.15 GitHub Actions Provider概念

```swift
import Foundation

struct DevStatus: Identifiable, Sendable, Equatable {
    var id: String
    var title: String
    var detail: String
    var state: DevStatusState
    var updatedAt: Date
}

enum DevStatusState: Sendable, Equatable {
    case running
    case success
    case failure
    case waiting
}
```

---

### 10.16 File Shelf Item

```swift
import Foundation

struct ShelfItem: Identifiable, Sendable, Equatable {
    var id: UUID
    var originalURL: URL
    var storedURL: URL
    var displayName: String
    var addedAt: Date
    var expiresAt: Date?
}
```

---

### 10.17 Temporary File Storage

```swift
import Foundation

final class TemporaryFileStorage {
    private let directory: URL

    init() throws {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        directory = appSupport
            .appendingPathComponent("Perch", isDirectory: true)
            .appendingPathComponent("Shelf", isDirectory: true)

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    func store(fileAt url: URL) throws -> URL {
        let destination = directory.appendingPathComponent(url.lastPathComponent)

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        try FileManager.default.copyItem(at: url, to: destination)
        return destination
    }
}
```

---

## 11. 設定項目案

```text
General:
  - Launch at login
  - Show menu bar icon
  - Start hidden
  - Enable sounds

Island:
  - Mode: Auto / Floating Pill / Physical Notch
  - Compact width
  - Compact height
  - Expanded width
  - Expanded height
  - Top offset
  - Animation speed
  - Auto collapse delay

Providers:
  - Claude
  - Codex
  - OpenAI
  - OpenRouter
  - Cursor
  - GitHub

AI:
  - Refresh interval
  - Show remaining / used
  - Show reset countdown
  - Warn when remaining below threshold

Shelf:
  - Enable file shelf
  - Auto delete after
  - Copy files / keep references
  - Enable AirDrop
  - Enable Quick Look

Dev:
  - GitHub repos
  - Workflow names
  - Local project folders
  - Notify on failure

Privacy:
  - Disable Keychain access
  - Disable browser cookie import
  - Clear cached provider data
  - Open config folder
```

---

## 12. データモデル概念

```text
AppState
  - isExpanded
  - activeCard
  - aiSnapshots
  - nowPlaying
  - shelfItems
  - devStatuses
  - latestError

AIUsageStore
  - providers
  - snapshots
  - refreshAll()

ShelfStore
  - items
  - addFiles()
  - removeItem()
  - cleanupExpired()

DevStatusStore
  - statuses
  - refreshGitHub()
  - refreshLocal()

NowPlayingManager
  - currentTrack
  - playbackState
  - sendCommand()
```

---

## 13. UI状態遷移

```text
Idle
  ↓ media starts
NowPlayingCompact
  ↓ hover
NowPlayingExpanded
  ↓ mouse leave
NowPlayingCompact
  ↓ timeout
Idle

Idle
  ↓ AI warning
AIUsageCompact
  ↓ click
AIUsageExpanded
  ↓ action
ProviderDetail

Idle
  ↓ file drag enters top area
FileShelfDropTarget
  ↓ drop
FileShelfExpanded
  ↓ timeout
Compact

Idle
  ↓ GitHub Actions failed
DevStatusAlert
  ↓ click
DevStatusExpanded
```

---

## 14. MVPスコープ

### v0.1

```text
- Swift + AppKit + SwiftUI
- Menu Bar App
- Dock iconなし
- ピル型UI
- ノッチあり/なし自動判定
- Compact / Expanded切り替え
- hover展開
- click展開
- Settings画面
- Login at launch
```

---

### v0.2

```text
- Now Playing表示
- 曲名/アーティスト
- 再生/停止
- 次へ/前へ
- アルバムアート
```

---

### v0.3

```text
- AI Usage基盤
- AIProvider protocol
- Claude Provider
- Codex Provider
- OpenAI Provider
- Providerカード表示
- RefreshScheduler
```

---

### v0.4

```text
- File Shelf
- Drag & Drop
- 一時保存
- ファイル一覧
- Quick Look
- AirDrop起動
- 自動削除
```

---

### v0.5

```text
- GitHub Actions Provider
- repo設定
- workflow状態表示
- failure時のピル通知
```

---

### v1.0

```text
- Sparkle update
- Homebrew Cask配布
- プロバイダー追加
- HUD表示
- 安定化
- README/Docs整備
```

---

## 15. 実装時の注意点

### 15.1 Window Level

`level = .statusBar + 8`のような高いレベルは便利だが、他アプリやメニューバーマネージャーと競合する可能性がある。

設定で以下を変更できるようにするとよい。

```text
- Normal
- StatusBar
- StatusBar + 1
- StatusBar + 8
```

---

### 15.2 マウスイベント

通常時は邪魔しない必要がある。

設計案:

```text
Compact時:
  - ピル部分だけイベントを受け取る

Expanded時:
  - 全体がイベントを受け取る

Idle時:
  - 必要に応じてignoresMouseEvents = true
```

---

### 15.3 フルスクリーン対応

`collectionBehavior`に以下を含める。

```swift
[
    .fullScreenAuxiliary,
    .stationary,
    .canJoinAllSpaces,
    .ignoresCycle
]
```

ただし、フルスクリーンアプリの上に常に出る挙動は好みが分かれるため、設定で切り替え可能にする。

---

### 15.4 複数ディスプレイ

初期実装では以下でよい。

```text
- built-in displayを優先
- なければmain screen
- 設定で表示ディスプレイを選択
```

将来的には、各ディスプレイに個別のPerchを出すか選べるようにする。

---

### 15.5 Provider認証

AI Provider系は認証方式が複雑になりやすい。

初期方針:

```text
- API key方式を優先
- CLI config読み取りは次点
- browser cookie読み取りは後回し
- Keychainアクセスは必要になるまで避ける
```

---

### 15.6 App Store配布

App Store配布は最初から狙わない。

理由:

```text
- window level制御
- provider認証
- browser cookie
- private APIの可能性
- Sparkle/Homebrew配布との相性
```

配布方針:

```text
- GitHub Releases
- Homebrew Cask
- Sparkle update
```

---

## 16. 開発優先順位

最初に作るべき順番:

```text
1. AppKit透明ウィンドウ
2. ピルUI
3. ノッチあり/なし判定
4. hover/click展開
5. Settings
6. Now Playing
7. AIProvider protocol
8. Claude/Codex Provider
9. File Shelf
10. GitHub Actions
```

最初からやらない方がいいもの:

```text
- HUD完全置き換え
- private API
- Objective-C++
- XPC helper
- プラグインシステム
- WidgetKit
- 大量Provider対応
- App Store配布
```

---

## 17. 最終イメージ

Perchは以下のような立ち位置を目指す。

```text
Boring Notch:
  ノッチを便利にする

NotchDrop:
  ノッチをファイル棚にする

CodexBar:
  AI使用量をメニューバーに出す

Perch:
  Mac上端中央を、AI・開発・メディア・ファイルのライブハブにする
```

短期的には、

```text
Dynamic Island風の上端ピル + AI使用量 + Now Playing + ファイル棚
```

長期的には、

```text
開発者向けライブアクティビティハブ
```

を目指す。
````
