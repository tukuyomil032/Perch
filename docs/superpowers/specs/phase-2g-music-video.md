# Phase 2g: Music Video / Ad Video in Artwork Frame (将来検討)

## Background
ユーザー要望: Spotify 広告動画・通常音楽のMVをアートワーク枠（100×100）に表示したい。

## 技術的実現可能性
- Spotify 広告: DistributedNotificationCenter 通知には広告サムネ/動画 URL が含まれない。
  Spotify Web API の広告エンドポイントは非公開。現状実現困難。
- 通常楽曲のMV: Apple Music は MusicKit で Video を取得可能（entitlement 必要）。
  Spotify は非公開。YouTube Music は YTM ブリッジ経由で取得可能性あり。
- プレイヤー: `AVPlayer` + SwiftUI `VideoPlayer` で実装可能。

## 決定
Phase 2g / Phase 3 以降で改めて検討。広告映像は Spotify が API を公開するまで実装しない。
通常楽曲 MV は MusicKit entitlement 取得後に Apple Music のみで試験実装を検討。
