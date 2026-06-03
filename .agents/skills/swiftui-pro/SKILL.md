---
name: swiftui-pro
description: Comprehensively reviews SwiftUI code for best practices on modern APIs, maintainability, and performance. Use when reading, writing, or reviewing SwiftUI projects.
license: MIT
metadata:
  author: Paul Hudson
  version: "1.1"
---

Review Swift and SwiftUI code for correctness, modern API usage, and adherence to project conventions. Report only genuine problems - do not nitpick or invent issues.

Review process:

1. Check for deprecated API using `references/api.md`.
1. Check that views, modifiers, and animations have been written optimally using `references/views.md`.
1. Validate that data flow is configured correctly using `references/data.md`.
1. Ensure navigation is updated and performant using `references/navigation.md`.
1. Ensure the code uses designs that are accessible and compliant with Apple’s Human Interface Guidelines using `references/design.md`.
1. Validate accessibility compliance including Dynamic Type, VoiceOver, and Reduce Motion using `references/accessibility.md`.
1. Ensure the code is able to run efficiently using `references/performance.md`.
1. Quick validation of Swift code using `references/swift.md`.
1. Final code hygiene check using `references/hygiene.md`.

If doing a partial review, load only the relevant reference files.


## Core Instructions

- iOS 26 exists, and is the default deployment target for new apps.
- Target Swift 6.2 or later, using modern Swift concurrency.
- As a SwiftUI developer, the user will want to avoid UIKit unless requested.
- Do not introduce third-party frameworks without asking first.
- Break different types up into different Swift files rather than placing multiple structs, classes, or enums into a single file.
- Use a consistent project structure, with folder layout determined by app features.


## Output Format

Organize findings by file. For each issue:

1. State the file and relevant line(s).
2. Name the rule being violated (e.g., "Use `foregroundStyle()` instead of `foregroundColor()`").
3. Show a brief before/after code fix.

Skip files with no issues. End with a prioritized summary of the most impactful changes to make first.

Example output:

### ContentView.swift

**Line 12: Use `foregroundStyle()` instead of `foregroundColor()`.**

```swift
// Before
Text("Hello").foregroundColor(.red)

// After
Text("Hello").foregroundStyle(.red)
```

**Line 24: Icon-only button is bad for VoiceOver - add a text label.**

```swift
// Before
Button(action: addUser) {
    Image(systemName: "plus")
}

// After
Button("Add User", systemImage: "plus", action: addUser)
```

**Line 31: Avoid `Binding(get:set:)` in view body - use `@State` with `onChange()` instead.**

```swift
// Before
TextField("Username", text: Binding(
    get: { model.username },
    set: { model.username = $0; model.save() }
))

// After
TextField("Username", text: $model.username)
    .onChange(of: model.username) {
        model.save()
    }
```

### Summary

1. **Accessibility (high):** The add button on line 24 is invisible to VoiceOver.
2. **Deprecated API (medium):** `foregroundColor()` on line 12 should be `foregroundStyle()`.
3. **Data flow (medium):** The manual binding on line 31 is fragile and harder to maintain.

End of example.


## References

- `references/accessibility.md` - Dynamic Type, VoiceOver, Reduce Motion, and other accessibility requirements.
- `references/api.md` - updating code for modern API, and the deprecated code it replaces.
- `references/design.md` - guidance for building accessible apps that meet Apple’s Human Interface Guidelines.
- `references/hygiene.md` - making code compile cleanly and be maintainable in the long term.
- `references/navigation.md` - navigation using `NavigationStack`/`NavigationSplitView`, plus alerts, confirmation dialogs, and sheets.
- `references/performance.md` - optimizing SwiftUI code for maximum performance.
- `references/data.md` - data flow, shared state, and property wrappers.
- `references/swift.md` - tips on writing modern Swift code, including using Swift Concurrency effectively.
- `references/views.md` - view structure, composition, and animation.

---

## Perch Project Rules

### Island UI Component Conventions
- 全カードコンポーネントは `IslandCardContainer` でラップすること
- compact表示とexpanded表示を必ずペアで実装
- `@Environment(AppState.self)` でAppStateにアクセス
- アニメーションは `DesignSystem.springAnimation` / `.expandAnimation` / `.subtleAnimation` を使用（ハードコードしない）

### DesignSystem Usage
- 色、フォント、スペーシング、角丸は `DesignSystem` の定数を使用
- ハードコードされたマジックナンバーを避ける
- 4pt gridに従う（padding: 8/12/16/20/24）

### Import Pitfalls
- `CGSize`, `CGFloat`, `CGRect` を使うファイルは `import CoreGraphics`（`import Foundation` では不十分）
- AppKit型を使わないモデルファイルでも幾何型を使うなら CoreGraphics が必要
- `NSImage` を使うビューは `import AppKit` が必要だが、`Image(nsImage:)` だけなら `import SwiftUI` で十分（SwiftUI がAppKitを再エクスポートするため）

### View Structure Pattern
```swift
struct SomeCard: View {
    @Environment(AppState.self) private var appState
    
    var body: some View {
        // expanded content
    }
    
    // MARK: - compact表示用
    static func compactLabel(from state: AppState) -> String? {
        // compact pill に表示するテキスト
    }
}
```

### GeometryReader Anti-Patterns
GeometryReader は強力だが誤用しやすい。以下の落とし穴を避けること:

```swift
// ❌ 進捗バーにGeometryReaderをトップレベルで使うと first-render flash が発生
// GeometryReaderはfirst-frameでsize=0を報告することがある
GeometryReader { geo in
    ZStack(alignment: .leading) {
        Capsule().fill(.white.opacity(0.15)).frame(height: 3)
        Capsule().fill(.white.opacity(0.7))
            .frame(width: geo.size.width * progress, height: 3)
    }
}
.frame(height: 3)

// ✅ overlayにGeometryReaderを配置する → trackが先にレイアウトされるため安定
Capsule()
    .fill(.white.opacity(0.15))
    .frame(height: 3)
    .overlay(alignment: .leading) {
        GeometryReader { geo in
            Capsule()
                .fill(.white.opacity(0.7))
                .frame(width: geo.size.width * progress, height: 3)
        }
    }

// ❌ テキスト幅測定に nested GeometryReader を使うと親サイズを継承して不正確
Text(text).background(
    GeometryReader { g in Color.clear }  // gは親のサイズを報告する
)

// ✅ PreferenceKey でテキストの自然な幅を測定する
private struct TextWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
Text(text).fixedSize().background(
    GeometryReader { g in Color.clear.preference(key: TextWidthKey.self, value: g.size.width) }
)
.onPreferenceChange(TextWidthKey.self) { contentWidth = $0 }
```

### @Observable State Animation on macOS
`@Observable` の状態変化は macOS では自動的にアニメーションコンテキストでラップされない。明示的な `.animation(value:)` が必要:

```swift
// ❌ @Observable の変化でtransitionがアニメーションしない
@ViewBuilder
private var pillContent: some View {
    if condition {
        ViewA().transition(.opacity)
    } else {
        ViewB().transition(.opacity)
    }
}

// ✅ Groupにanimationを付ける
@ViewBuilder
private var pillContent: some View {
    Group {
        if condition {
            ViewA().transition(.opacity)
        } else {
            ViewB().transition(.opacity)
        }
    }
    .animation(DesignSystem.springAnimation, value: condition)
}
```

### Multiple scaleEffect Animation Conflicts
複数の `State` が同じ `scaleEffect` を共有する場合、アニメーション競合が発生する:

```swift
// ❌ isBouncing変化時にisHoveredのanimationが干渉する
.scaleEffect(isBouncing ? 1.05 : (isHovered ? 1.03 : 1.0))
.animation(springAnimation, value: isHovered)  // isBouncing変化でも発火してしまう

// ✅ 各変数に専用のanimationを付ける
.scaleEffect(isBouncing ? 1.05 : (isHovered ? 1.03 : 1.0))
.animation(.spring(response: 0.2, dampingFraction: 0.5), value: isBouncing)
.animation(springAnimation, value: isHovered)
```

### TimelineView for Live-Updating Progress
MRMediaRemote は毎秒通知を発火しない。タイムスタンプキー + `TimelineView` でリアルタイム進捗を表示:

```swift
// NowPlayingState に timestamp を保持
let timestamp: Date?  // MRInfoKey.timestamp から取得
func liveProgress(at date: Date) -> Double {
    guard let elapsed = elapsedTime, let total = duration, total > 0 else { return 0 }
    guard isPlaying, let ts = timestamp else { return min(elapsed / total, 1.0) }
    return min((elapsed + date.timeIntervalSince(ts)) / total, 1.0)
}

// NowPlayingCard でTimelineViewを使用
TimelineView(.animation(minimumInterval: 1.0, paused: !state.isPlaying)) { context in
    progressBar(at: context.date)
}
```

**minimumInterval: 1.0** — 進捗バーには1秒更新で十分。60fpsは不要でバッテリー効率が悪い。`paused: !state.isPlaying` で一時停止中は更新を停止する。

### MarqueeText (Auto-scrolling Text) Best Practices
- `onPreferenceChange` はレイアウトパスごとに発火するため、`guard offset == 0 else { return }` で再エントリーを防ぐ
- `asyncAfter` の代わりに `Task { @MainActor in try? await Task.sleep(...) }` + `scrollGeneration` Int で非同期キャンセルを実現
- `autoreverses: false` + `repeatForever` が標準的なマーキーUX（autoreverses: trueは往復して非ネイティブに見える）
- `containerWidth` は `onAppear` だけでなく `.onChange(of: geo.size.width)` でも更新する（マルチディスプレイ対応）

### NSImage in @MainActor Struct — Equatable Pitfalls (Swift 6)
`@MainActor struct` に `NSImage?` プロパティを持ち、`Equatable` を `nonisolated` で実装する場合:

```swift
// ❌ NSImageはnon-Sendable。nonisolated ==でアクセスするとSwift 6 CIエラー
// （ローカルはSWIFT_DEFAULT_ACTOR_ISOLATION=MainActorで通過しても、CIで失敗する）
nonisolated static func == (lhs: NowPlayingState, rhs: NowPlayingState) -> Bool {
    lhs.title == rhs.title && lhs.artist == rhs.artist
        && lhs.artwork === rhs.artwork  // ❌ NSImage? in nonisolated context
}

// ❌ &&のRHSは@autoclosure。NSImage?を@autoclosure内で使うと別エラーが出る場合も
nonisolated static func == (lhs: NowPlayingState, rhs: NowPlayingState) -> Bool {
    guard lhs.title == rhs.title, lhs.artist == rhs.artist else { return false }
    return lhs.artwork === rhs.artwork  // ❌ still non-Sendable in nonisolated func
}

// ✅ NSImageをEquatableの比較から除外。Sendableなフィールドのみ比較する。
// アートワーク変化検出が必要な場合は artworkID: Int? (Data.hashValue) を追加する
nonisolated static func == (lhs: NowPlayingState, rhs: NowPlayingState) -> Bool {
    lhs.title == rhs.title && lhs.artist == rhs.artist && lhs.isPlaying == rhs.isPlaying
}
```

**ルール**: Swift 6 strictモードでは、`@MainActor` struct の non-Sendable プロパティ（`NSImage`, `NSAttributedString` 等）を `nonisolated` 関数から読み取ることはできない。ローカルビルドが `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor` で通っていてもCIで落ちる。
