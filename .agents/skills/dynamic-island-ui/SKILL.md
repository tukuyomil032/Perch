# Dynamic Island UI

iOSのDynamic Islandにインスパイアされたピル型UIの実装ガイド。compact/expandedモーフィング、アニメーション、カード切り替え、hover/click UXをカバーする。

## When to Use
- ピルUIの実装・修正時
- compact↔expanded遷移のアニメーション実装時
- カード切り替えUI実装時
- hover/clickインタラクション実装時
- 新規カードの追加時

## Animation Constants

全てのアニメーションは `DesignSystem` の定数を使用すること。ハードコード禁止。

```swift
enum DesignSystem {
    static let springAnimation = Animation.spring(response: 0.32, dampingFraction: 0.82)
    static let expandAnimation = Animation.spring(response: 0.35, dampingFraction: 0.86)
    static let subtleAnimation = Animation.easeInOut(duration: 0.2)
}
```

## Compact ↔ Expanded Morphing

### matchedGeometryEffect
```swift
@Namespace private var animation

if appState.isExpanded {
    ExpandedIslandView()
        .matchedGeometryEffect(id: "island", in: animation)
        .transition(.scale(scale: 0.92).combined(with: .opacity))
} else {
    CompactPillView()
        .matchedGeometryEffect(id: "island", in: animation)
        .transition(.scale(scale: 0.92).combined(with: .opacity))
}
```

### Window Frame Animation
ウィンドウサイズはAppKit側で `window.animator().setFrame()` を使用。
SwiftUIのアニメーションとAppKitのframeアニメーションを同期させる。

## Compact Pill Design

- 背景: NSVisualEffectView ultraDark material（半透明vibrancy）
- 形状: Capsule
- 高さ: 34pt、幅: 可変（min 150pt）
- 左: ステータスインジケーター（6pt Circle）
- 中央: コンテキスト依存ラベル
- hover: スケール1.03 + subtle glow
- クリック: 即時展開

## Expanded Card Design

- 背景: NSVisualEffectView ultraDark material
- 形状: RoundedRectangle(cornerRadius: 28, style: .continuous)
- 幅: 420pt、高さ: カード内容依存
- ヘッダー: 左"Perch" + 右カード名
- padding: 16pt（DesignSystem.cardPadding）
- カード切り替え: 左右スワイプ or ページインジケーター

## Hover / Click UX

### hover展開
1. マウスがピル領域に入る
2. 0.3秒ディレイ（意図的なhoverか判定）
3. ディレイ後に展開トリガー
4. スケール1.03 + glow effectをディレイ中に表示

### click展開
- クリックで即時展開（ディレイなし）
- ディレイ待ち中のクリックも即時展開

### 自動収納
- マウスがexpanded領域外に出たら3秒タイマー開始
- 操作中（スクロール、クリック等）はタイマーリセット
- タイマー満了でcompactに収納

## Notification Animation

イベント発生時のピル通知:
1. ピルが一時的に膨張（scale 1.1 → 1.0）
2. 内容テキスト表示（例: "❌ Build failed"）
3. 3秒後に元のコンテキストに戻る
4. 重要度に応じてglow色変更（赤: failure、オレンジ: warning）

## Adding a New Card

新規カードを追加する手順:
1. `IslandCard` enumにcaseを追加
2. `Features/<Name>/` にデータモデルとマネージャーを作成
3. `UI/Cards/<Name>Card.swift` にカードViewを作成
4. `CompactPillView.compactLabel` に表示ロジックを追加
5. `ExpandedIslandView` のswitch文にカードを追加
6. `AppState` に必要なプロパティを追加

## Common Pitfalls
- `matchedGeometryEffect`のidは一意にすること（複数のmatchedGeometryが衝突する）
- Spring animationのパラメータを変えると全体の一貫性が崩れる → DesignSystem経由
- vibrancyはSwiftUIの`.background(.ultraThinMaterial)`ではなくAppKitのNSVisualEffectViewを使う（より制御しやすい）
- hover検知はNSTrackingAreaが確実。SwiftUIの`.onHover`はウィンドウ外で不安定な場合がある
