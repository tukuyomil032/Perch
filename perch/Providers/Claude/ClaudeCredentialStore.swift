import Foundation
import Security

// MARK: - Credential resolution (read-only, priority order)

nonisolated enum ClaudeCredentialResolver {
    /// Resolves the OAuth access token using this priority:
    /// 1. CLAUDE_CODE_OAUTH_TOKEN env var (official Claude Code env var)
    /// 2. ~/.claude/.credentials.json → claudeAiOauth.accessToken
    /// 3. macOS Keychain via /usr/bin/security (Claude Code-credentials / oauth.claude)
    /// 4. Perch Keychain (com.tukuyomi032.perch.claude) for manually entered tokens
    static func resolveAccessToken() -> String? {
        let env = ProcessInfo.processInfo.environment
        if let token = normalized(env["CLAUDE_CODE_OAUTH_TOKEN"]) { return token }
        if let token = credentialsJsonToken() { return token }
        if let token = claudeCodeKeychainToken() { return token }
        return try? ClaudeCredentialStore.loadAccessToken()
    }

    private static func normalized(_ value: String?) -> String? {
        guard let v = value?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return nil }
        return v
    }

    /// Reads ~/.claude/.credentials.json with the claudeAiOauth.accessToken structure
    /// used by Claude Code CLI on Linux/Windows.
    private static func credentialsJsonToken() -> String? {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
        guard let data = try? Data(contentsOf: path),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let oauth = json["claudeAiOauth"] as? [String: Any],
            let token = oauth["accessToken"] as? String,
            !token.isEmpty
        else { return nil }
        return token
    }

    /// Reads Claude Code's macOS Keychain entry via /usr/bin/security subprocess.
    /// Claude Code stores credentials as JSON under service="Claude Code-credentials" / account="oauth.claude".
    /// Using the security CLI avoids ACL restrictions that block direct SecItemCopyMatching from other apps.
    private static func claudeCodeKeychainToken() -> String? {
        let securityPath = "/usr/bin/security"
        guard FileManager.default.isExecutableFile(atPath: securityPath) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: securityPath)
        process.arguments = [
            "find-generic-password",
            "-s", "Claude Code-credentials",
            "-w",
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        let deadline = Date().addingTimeInterval(1.5)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if process.isRunning {
            process.terminate()
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }

        let raw = pipe.fileHandleForReading.readDataToEndOfFile()
        guard
            let trimmed = String(data: raw, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmed.isEmpty
        else { return nil }

        // The stored data is JSON: {"claudeAiOauth": {"accessToken": "sk-ant-oat..."}}
        guard let jsonData = trimmed.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
            let oauth = json["claudeAiOauth"] as? [String: Any],
            let token = oauth["accessToken"] as? String,
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
