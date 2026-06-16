import Foundation

nonisolated struct ClaudeProvider: AIProvider {
    let id = "claude"
    let displayName = "Claude"
    let brandColorHex = "#E8784F"
    let icon = "message.circle.fill"

    private let oauthClient = ClaudeOAuthUsageClient()

    nonisolated var isConfigured: Bool {
        ClaudeCredentialResolver.resolveAccessToken() != nil
            || FileManager.default.fileExists(atPath: projectsDir.path)
    }

    nonisolated private var projectsDir: URL {
        if let envPath = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] {
            return URL(fileURLWithPath: envPath).appendingPathComponent("projects")
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let xdgPath = home.appendingPathComponent(".config/claude/projects")
        if FileManager.default.fileExists(atPath: xdgPath.path) { return xdgPath }
        return home.appendingPathComponent(".claude/projects")
    }

    nonisolated func fetchUsage() async throws -> AIUsageData {
        async let localResult = fetchLocal(dir: projectsDir)
        async let remoteResult = fetchRemote()
        return ClaudeUsageMerger.merge(remote: await remoteResult, local: await localResult)
    }

    private nonisolated func fetchLocal(dir: URL) async -> Result<ClaudeLocalUsage, ClaudeProviderError> {
        do {
            let usage = try await Task.detached(priority: .utility) {
                try ClaudeLocalUsageParser.parseUsage(in: dir)
            }.value
            return .success(usage)
        } catch let err as ClaudeProviderError {
            return .failure(err)
        } catch {
            return .failure(.localParsing(error))
        }
    }

    private nonisolated func fetchRemote() async -> Result<ClaudeLimitUsage, ClaudeProviderError> {
        guard let token = ClaudeCredentialResolver.resolveAccessToken() else {
            return .failure(.missingCredential)
        }
        do {
            let limits = try await oauthClient.fetchUsage(accessToken: token)
            return .success(limits)
        } catch let err as ClaudeProviderError {
            return .failure(err)
        } catch {
            return .failure(.decoding(error))
        }
    }
}
