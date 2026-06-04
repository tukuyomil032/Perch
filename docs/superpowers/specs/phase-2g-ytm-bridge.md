# Phase 2g: YTM TypeScript Bridge

## Goal
YouTube Music の再生コントロール（play/pause/next/prev）を AppleScript ではなく
TypeScript ブリッジ経由で実装する。合わせて Pattern 5 没入型歌詞の基盤とする。

## モノレポ配置
perch リポジトリ内の `perch/Bridge/` ディレクトリに配置する。
Swift ↔ TS 通信は stdio JSON-RPC または Unix socket（設計フェーズで決定）。

## 採用技術（案）
- Runtime: Node.js / Bun（軽量）
- Language: TypeScript
- Browser automation: Chrome DevTools Protocol (CDP) via Puppeteer または playwright-core
- 通信: Swift Process + stdio pipe or NSXPCConnection

## 機能スコープ
1. YTM タブ検出（既存 NSWorkspace.runningApplications と連携）
2. play / pause / next / prev コマンド送信
3. 現在の曲情報 JSON を stdout にストリーム
4. （Pattern 5 基盤）LRC 歌詞取得 & 現在行インデックスの計算

## 未決事項
- Swift ↔ TS IPC プロトコル（stdio vs socket vs XPC）
- バンドル方式（esbuild single binary vs pkg）
- TS ブリッジのライフサイクル管理（AppDelegate から spawn）
- lrclib-api TS ラッパー使用可否（Swift 側で完結するなら不要）

## 既知の制限
- Spotify / Apple Music には適用しない（AppleScript で十分）
- ブリッジクラッシュ時のフォールバックが必要（既存 JS injection にダウングレード）
