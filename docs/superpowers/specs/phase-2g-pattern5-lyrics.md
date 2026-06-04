# Phase 2g: Pattern 5 Immersive Lyrics View

## Goal
再生中アートワークをぼかした背景に歌詞を大きく表示する没入型ビュー。
iOS 26 Apple Music の歌詞画面に近いデザイン。

## UI 仕様（案）
- 展開カード全面: アートワーク背景（ブラー + 暗化）
- 歌詞テキスト: 大きめ（18-22pt）、行レベル bold/dim
- アクティブ行: 白 opacity 1.0、semibold
- 過去行: opacity 0.45、regular
- 未来行: opacity 0.30、regular
- スクロール: activeIndex が上から 30% に来るようスムーズ追従
- ミニコントロール: 下端に ⏮ ⏸/▶ ⏭ + 閉じる

## Pattern 2 との違い
Pattern 2: 縦長スクロールリスト（12pt、2カラム交互）
Pattern 5: 全画面背景 + 大きな歌詞（アートワーク背景）

## 依存関係
- YTM TypeScript ブリッジ（Phase 2g-A）完成後に実装
- Apple Music / Spotify は既存実装で対応可

## word-level ハイライトについて
行レベル（LRCLIB）で確定。Apple MusicKit の word-level TTML は
entitlement + ユーザー Apple Music サブスクが必要なため、本プロジェクトでは実装しない。
