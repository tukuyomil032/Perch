# AppKit Window Control

macOS AppKitのNSWindow/NSPanel制御に関する実装ガイド。Perchの透明オーバーレイウィンドウ、level管理、Spaces対応、マウスイベント制御をカバーする。

## When to Use
- NSWindow/NSPanelの作成・設定時
- ウィンドウの透明化・borderless設定時
- window level制御時
- Spaces/フルスクリーン対応時
- マウスイベントのパススルー制御時

## Transparent Overlay Window

### Required Setup
```swift
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
        level = .statusBar + 1
    }
}
```

### Key Points
- `isOpaque = false` + `backgroundColor = .clear` で透明背景
- `.borderless` でタイトルバーなし
- `.fullSizeContentView` でコンテンツがウィンドウ全体を使用

## Window Level

| Level | Use Case |
|-------|----------|
| `.normal` | 通常。他アプリの後ろに隠れる |
| `.statusBar` | メニューバーと同じ。基本的にはこれ |
| `.statusBar + 1` | メニューバーの上。Perchのデフォルト |
| `.statusBar + 8` | 最前面寄り。他アプリのオーバーレイと競合する可能性 |

設定で変更可能にすること。`level`は`NSWindow.Level`型。

## Spaces / Fullscreen

### collectionBehavior フラグ
- `.canJoinAllSpaces`: 全Spacesに表示
- `.stationary`: Space切り替え時に動かない
- `.fullScreenAuxiliary`: フルスクリーンアプリの上に表示
- `.ignoresCycle`: Cmd+Tab/Cmd+`の対象外

### フルスクリーン設定
設定で「フルスクリーン時に表示」を切り替え可能にする。
一部ユーザーはフルスクリーン時にPerchを非表示にしたい。

## Mouse Event Passthrough

### compact時
ピル領域のみイベントを受け取り、それ以外は背面のアプリにパススルー。

方法1: `ignoresMouseEvents`を動的に制御
```swift
override func hitTest(_ point: NSPoint) -> NSView? {
    // ピル領域内ならself、外ならnil（パススルー）
}
```

方法2: SwiftUI側で`.contentShape`を使って当たり判定を制御
```swift
.contentShape(Capsule())
```

### expanded時
カード全体がイベント受け取り。
`ignoresMouseEvents = false`。

## NSHostingController Integration

```swift
let rootView = RootIslandView()
    .environment(appState)
let hostingController = NSHostingController(rootView: rootView)
window.contentViewController = hostingController
```

## Screen Change Monitoring

```swift
NotificationCenter.default.addObserver(
    forName: NSApplication.didChangeScreenParametersNotification,
    object: nil,
    queue: .main
) { _ in
    // ディスプレイ変更時の再配置
}
```

## Xcode Project Notes
- Perchは `PBXFileSystemSynchronizedRootGroup` を使用。ファイルシステム上でファイルを追加/移動すればXcodeが自動同期するため、pbxproj手動編集は不要
- SPMパッケージ依存の追加はXcode GUIから行うこと（CLIからのpbxproj編集は破損リスクが高い）
- NSWindow/NSPanel サブクラスには `@MainActor` を明示すること（NSWindow自体が@MainActorだがプロジェクト規約として明示）

## Common Pitfalls
- `canBecomeMain`をtrueにすると他アプリのフォーカスを奪う → `false`推奨
- `canBecomeKey`はtrueにしないとキーボード入力を受け取れない
- `hasShadow`をtrueにするとCompact時に余計な影が出る → 動的に制御
- `level`を高くしすぎると他のメニューバーマネージャーと競合する
