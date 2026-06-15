import Foundation
import Security

// MARK: - Credential resolution (read-only, priority order)

nonisolated enum ClaudeCredentialResolver {
    /// Resolves the OAuth access token using this priority:
    /// 1. CLAUDE_OAUTH_TOKEN env var
    /// 2. ANTHROPIC_OAUTH_TOKEN env var
    /// 3. ~/.claude/.credentials.json (Claude Code's own credential file)
    /// 4. Perch Keychain (com.tukuyomi032.perch.claude)
    static func resolveAccessToken() -> String? {
        let env = ProcessInfo.processInfo.environment
        if let token = normalized(env["CLAUDE_OAUTH_TOKEN"]) { return token }
        if let token = normalized(env["ANTHROPIC_OAUTH_TOKEN"]) { return token }
        if let token = credentialsJsonToken() { return token }
        return try? ClaudeCredentialStore.loadAccessToken()
    }

    private static func normalized(_ value: String?) -> String? {
        guard let v = value?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return nil }
        return v
    }

    private static func credentialsJsonToken() -> String? {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
        guard let data = try? Data(contentsOf: path),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let token = json["access_token"] as? String,
            !token.isEmpty
        else { return nil }
        return token
    }
}

// MARK: - Perch-owned Keychain storage (for manually entered tokens)

nonisolated enum ClaudeCredentialStore {
    private static let service = "com.tukuyomi032.perch.claude"
    private static let account = "oauth-access-token"

    static func saveAccessToken(_ token: String) throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CredentialError.emptyToken }
        guard let data = trimmed.data(using: .utf8) else { throw CredentialError.encodingFailed }

        let base: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        SecItemDelete(base as CFDictionary)

        var insert = base
        insert[kSecValueData] = data
        insert[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else { throw CredentialError.keychain(status) }
    }

    static func loadAccessToken() throws -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw CredentialError.keychain(status) }
        guard let data = result as? Data, let token = String(data: data, encoding: .utf8)
        else { throw CredentialError.decodingFailed }
        return token
    }

    static func deleteAccessToken() throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound
        else { throw CredentialError.keychain(status) }
    }
}

nonisolated enum CredentialError: LocalizedError {
    case emptyToken, encodingFailed, decodingFailed
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .emptyToken: return "Token is empty."
        case .encodingFailed: return "Token could not be encoded."
        case .decodingFailed: return "Stored token could not be decoded."
        case .keychain(let s): return "Keychain error: \(s)"
        }
    }
}
