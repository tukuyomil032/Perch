# Perch デザインリファレンス

## Apple Dynamic Island

### 公式リソース
- Apple Developer: Live Activities — https://developer.apple.com/design/human-interface-guidelines/live-activities
- WWDC22 "Meet the expanded Dynamic Island" session
- WWDC23 "Design dynamic Live Activities" session

### 動画リファレンス
- Apple "Introducing Dynamic Island on iPhone 14 Pro" — YouTube公式チャンネル
- Apple "A Guided Tour of iPhone 14 Pro" — Dynamic Islandセクション

### インタラクションパターン
- compact: 小さなピル型。左右に分離可能（iOS）。Perchでは単一ピルとして使用
- minimal: 片側のみのコンパクト表示。Perchではcompactに統合
- expanded: タップで展開。コンテンツに応じた可変高さ
- 遷移: Spring animation、morphing effect、連続的なサイズ変化

### アニメーション特性
- 展開/収縮: bouncy spring（response ~0.35s, dampingFraction ~0.8）
- コンテンツ切り替え: crossfade + subtle scale
- 通知表示: ピルが一時的に膨張 → 内容表示 → 収縮
- 音楽再生: アルバムアートがピル端でbounce

---

## 参考プロジェクト

### Boring Notch
- リポジトリ: https://github.com/TheBoredTeam/boring.notch
- 参考ポイント:
  - Dynamic Island風の展開UI実装
  - Now Playing統合（MRMediaRemote使用）
  - 音楽コントロールUI
  - ファイル棚機能
  - macOS HUD置き換えアプローチ
  - 拡張システムの設計思想
- UI参考: README内のスクリーンショット・GIF

### NotchDrop
- リポジトリ: https://github.com/Lakr233/NotchDrop
- 参考ポイント:
  - 透明オーバーレイウィンドウ実装（NSWindow/NSPanel）
  - ノッチ検出ロジック（safeAreaInsets.top, auxiliaryTopLeftArea/RightArea）
  - ノッチなし環境のfallbackサイズ
  - ファイルドラッグ&ドロップ実装
  - AirDrop統合
  - Security-scoped bookmark処理
- コード参考: WindowController、NotchDetector周り

### CodexBar
- リポジトリ: https://github.com/steipete/CodexBar
- 参考ポイント:
  - AI Provider別のCore分離設計
  - バックグラウンド更新ループ（RefreshScheduler的な実装）
  - CLIとUIの分離アーキテクチャ
  - 設定管理パターン
  - Provider状態のUI表示
  - Sparkle自動アップデート統合
  - KeyboardShortcuts統合
  - privacy-firstなローカル処理

---

## macOSネイティブUI参考

### vibrancy / material
- NSVisualEffectView materials: `.ultraDark`, `.dark`, `.mediumLight`
- SwiftUI: `.background(.ultraThinMaterial)` 等
- Perchでは `.ultraDark` をベースに、macOSの半透明感を活かす

### Human Interface Guidelines
- macOS Design Themes: https://developer.apple.com/design/human-interface-guidelines/designing-for-macos
- Menus and actions: https://developer.apple.com/design/human-interface-guidelines/menus
- Settings: https://developer.apple.com/design/human-interface-guidelines/settings

### SF Symbols
- SF Symbols 6: https://developer.apple.com/sf-symbols/
- 使用箇所: MenuBar icon、カード内アクションボタン、ステータスインジケーター

---

## デザイン原則（Perch固有）

1. **macOSネイティブ感**: vibrancy、system font、SF Symbols。iOSの移植ではなくmacOSとして自然に振る舞う
2. **Dynamic Island的遷移**: compact↔expandedのmorphing、Spring animation、連続的なサイズ変化
3. **控えめな存在感**: compact時は邪魔にならない。必要な時だけ主張する
4. **統一されたデザインシステム**: 全カード共通のcornerRadius、padding、typography、animation timing
5. **hallmark(Anti-AI-Slop)準拠**: 構造的多様性、4pt grid、8状態設計

---

## docs/img/ について

このディレクトリにはデザイン参考用の画像・GIFを保存する。
- Apple Dynamic Islandのスクリーンショット
- Boring Notch / NotchDropのUI参考画像
- Perchのモックアップ・ワイヤーフレーム（作成時）
