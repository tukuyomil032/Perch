# AI Provider Integration

AI使用量監視のためのProvider実装ガイド。AIProvider protocol、認証フロー、エラーハンドリング、RefreshScheduler連携をカバーする。

## When to Use
- 新規AI Providerの追加時
- 認証フロー（Keychain/config/env）の実装時
- Provider設定UIの実装時
- 使用量データの取得・表示時

## AIProvider Protocol

```swift
protocol AIProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    var iconName: String { get }  // SF Symbol name
    
    func refresh() async throws -> AIUsageSnapshot
    func isConfigured() -> Bool
}
```

全Providerはこのprotocolに準拠する。`Sendable`必須（actor境界を越えるため）。

## Authentication Priority

1. **API key**: Settings画面でユーザーが入力 → Keychain保存
2. **CLI config**: ローカル設定ファイル読み取り（~/.claude/, ~/.codex/）
3. **Environment variable**: ANTHROPIC_API_KEY 等

### Keychain Management
```swift
import Security

enum KeychainHelper {
    static func save(service: String, account: String, data: Data) -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        return SecItemAdd(query as CFDictionary, nil)
    }
    
    static func load(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)
        return result as? Data
    }
}
```

サービス名規則: `com.tukuyomi032.perch.<provider-id>`

## Data Models

```swift
struct AIUsageSnapshot: Identifiable, Sendable, Equatable {
    var id: String
    var providerName: String
    var primaryWindow: UsageWindow?
    var secondaryWindow: UsageWindow?
    var lastUpdated: Date
    var status: ProviderStatus
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

## AIUsageStore Pattern

```swift
@MainActor @Observable
final class AIUsageStore {
    private(set) var snapshots: [AIUsageSnapshot] = []
    private let providers: [AIProvider]

    func refreshAll() async {
        await withTaskGroup(of: AIUsageSnapshot?.self) { group in
            for provider in providers {
                group.addTask {
                    do { return try await provider.refresh() }
                    catch {
                        return AIUsageSnapshot(
                            id: provider.id,
                            providerName: provider.displayName,
                            lastUpdated: Date(),
                            status: .error(error.localizedDescription)
                        )
                    }
                }
            }
            var next: [AIUsageSnapshot] = []
            for await snapshot in group {
                if let snapshot { next.append(snapshot) }
            }
            snapshots = next.sorted { $0.providerName < $1.providerName }
        }
    }
}
```

## RefreshScheduler Integration

```swift
let scheduler = RefreshScheduler()
await scheduler.start(interval: .seconds(300)) {
    await usageStore.refreshAll()
}
```

設定可能な間隔: 1分 / 5分 / 15分 / 手動

## Error Handling

- API認証失敗: `.error("Authentication failed")` → Settings画面へ誘導
- ネットワークエラー: `.error("Network error")` → リトライはRefreshScheduler任せ
- Rate limit: `.error("Rate limited")` → ポーリング間隔を自動延長
- Config not found: `isConfigured()` で false → UIで未設定表示
- stale data: 最後の更新から設定間隔の3倍経過 → `.stale`

## Adding a New Provider

1. `Providers/<Name>/` ディレクトリ作成
2. `<Name>Provider.swift` で `AIProvider` protocolに準拠
3. `<Name>Credentials.swift` で認証管理（Keychain/config）
4. `AIUsageStore` のproviders配列に追加
5. Settings UIにProvider設定を追加
6. テスト: `refresh()` が正常にAIUsageSnapshotを返すか確認

## Common Pitfalls
- `refresh()` はNetworkエラーを投げる可能性がある → 必ずdo/catchで処理
- Keychainアクセスはmain threadで行っても問題ないが、ファイルI/Oが大きい場合はバックグラウンドで
- CLI config読み取り時はファイルの存在チェックを先に行う
- Provider追加時はCodexBarの同等Provider実装を参考にする
