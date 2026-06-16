import Foundation

// Codex CLI (TUI mode) stores session logs at ~/.codex/sessions/YYYY/MM/DD/*.jsonl
// Each file = one session. We parse the last `token_count` event per session for cumulative totals.
// Note: Codex Desktop (GUI) does NOT write JSONL — those sessions are untrackable.
nonisolated struct CodexProvider: AIProvider {
    let id = "codex"
    let displayName = "Codex"
    let brandColorHex = "#22D3EE"  // cyan-400
    let icon = "terminal"

    nonisolated var isConfigured: Bool {
        FileManager.default.fileExists(atPath: sessionsDir.path)
    }

    private var sessionsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions")
    }

    nonisolated func fetchUsage() async throws -> AIUsageData {
        let dir = sessionsDir

        // ローカル解析と WHAM 取得を並列実行
        async let localResult: AIUsageData? = Task.detached(priority: .utility) {
            try? Self.parseSessions(in: dir)
        }.value

        var whamTiers: (session: UsageTier, weekly: UsageTier)?
        var warningMsg: String?

        if let creds = Self.resolveCredentials() {
            whamTiers = try? await Self.fetchWhamLimits(
                accessToken: creds.accessToken, accountId: creds.accountId)
            if whamTiers == nil {
                warningMsg = "公式使用量取得失敗: WHAM API エラー"
            }
        } else {
            warningMsg = "公式使用量取得失敗: ~/.codex/auth.json が見つかりません"
        }

        var data = await localResult ?? AIUsageData(planName: "Codex", lastUpdated: Date())
        data.session = whamTiers?.session
        data.weekly = whamTiers?.weekly
        data.warningMessage = warningMsg
        return data
    }

    // MARK: - Credential Resolution

    private nonisolated static func resolveCredentials() -> (accessToken: String, accountId: String)? {
        if let creds = credentialsFromFile() { return creds }
        if let creds = credentialsFromKeychain() { return creds }
        return nil
    }

    private nonisolated static func credentialsFromFile() -> (String, String)? {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/auth.json")
        guard let data = try? Data(contentsOf: path),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tokens = json["tokens"] as? [String: Any],
            let accessToken = tokens["access_token"] as? String, !accessToken.isEmpty,
            let accountId = tokens["account_id"] as? String, !accountId.isEmpty
        else { return nil }
        return (accessToken, accountId)
    }

    private nonisolated static func credentialsFromKeychain() -> (String, String)? {
        let securityPath = "/usr/bin/security"
        guard FileManager.default.isExecutableFile(atPath: securityPath) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: securityPath)
        process.arguments = ["find-generic-password", "-s", "Codex Auth", "-w"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        let sema = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in sema.signal() }

        do { try process.run() } catch { return nil }

        if sema.wait(timeout: .now() + 1.5) == .timedOut {
            process.terminate()
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }

        let raw = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let trimmed = String(data: raw, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmed.isEmpty,
            let jsonData = trimmed.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
            let tokens = json["tokens"] as? [String: Any],
            let accessToken = tokens["access_token"] as? String, !accessToken.isEmpty,
            let accountId = tokens["account_id"] as? String, !accountId.isEmpty
        else { return nil }

        return (accessToken, accountId)
    }

    // MARK: - WHAM API

    private nonisolated static func fetchWhamLimits(
        accessToken: String, accountId: String
    ) async throws -> (session: UsageTier, weekly: UsageTier)? {
        guard let url = URL(string: "https://chatgpt.com/backend-api/wham/usage") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rateLimit = root["rate_limit"] as? [String: Any]
        else { return nil }

        func parseTier(_ window: [String: Any], label: String, defaultPeriod: TimeInterval) -> UsageTier? {
            let percentLeft =
                (window["percent_left"] as? Double)
                ?? (window["remaining_percent"] as? Double)
                ?? 100.0
            let usedFraction = max(0, min(1, 1.0 - percentLeft / 100.0))
            let resetMs = (window["reset_time_ms"] as? Double) ?? (window["reset_at"] as? Double)
            let resetsAt = resetMs.map { Date(timeIntervalSince1970: $0 / 1000.0) }
            let period = (window["limit_window_seconds"] as? Double) ?? defaultPeriod
            return UsageTier(
                usedFraction: usedFraction, resetsAt: resetsAt,
                label: label, source: .chatgptOAuth, periodDuration: period)
        }

        let sessionTier = (rateLimit["primary_window"] as? [String: Any])
            .flatMap { parseTier($0, label: "セッション", defaultPeriod: 5 * 3600) }
        let weeklyTier = (rateLimit["secondary_window"] as? [String: Any])
            .flatMap { parseTier($0, label: "週間", defaultPeriod: 7 * 24 * 3600) }

        guard let s = sessionTier, let w = weeklyTier else { return nil }
        return (s, w)
    }

    // MARK: - Parsing

    private nonisolated static func parseSessions(in dir: URL) throws -> AIUsageData {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.path) else {
            return AIUsageData(planName: "Codex", lastUpdated: Date())
        }

        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.timeZone = .current

        let now = Date()
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
        let todayKey = dayFormatter.string(from: now)

        var dayToCost: [String: Double] = [:]
        var dayToInputTokens: [String: Int] = [:]
        var dayToOutputTokens: [String: Int] = [:]
        var modelCost: [String: Double] = [:]
        var modelTotalTokens: [String: Int] = [:]

        let decoder = JSONDecoder()

        guard
            let enumerator = fm.enumerator(
                at: dir,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        else { return AIUsageData(planName: "Codex", lastUpdated: now) }

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jsonl" else { continue }

            // Filter by directory date (YYYY/MM/DD structure) before reading file
            let parentDir = fileURL.deletingLastPathComponent()
            if let dirDate = dateFromDayDir(parentDir), dirDate < thirtyDaysAgo { continue }
            let sessionKey = dateFromDayDir(parentDir).map { dayFormatter.string(from: $0) } ?? todayKey

            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

            // Per session: find last turn_context (model) and last token_count (cumulative)
            var sessionModel: String?
            var lastTokenCount: CodexTotalUsage?

            for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
                guard let event = try? decoder.decode(CodexEvent.self, from: Data(line.utf8)) else { continue }

                switch event.type {
                case "turn_context":
                    if let model = event.payload?.model { sessionModel = model }
                case "event_msg":
                    if event.payload?.type == "token_count",
                        let totals = event.payload?.info?.totalTokenUsage
                    {
                        lastTokenCount = totals
                    }
                default:
                    break
                }
            }

            guard let tokenCount = lastTokenCount, let model = sessionModel else { continue }

            // cached_input_tokens is a subset of input_tokens
            let cachedInput = tokenCount.cachedInputTokens ?? 0
            let nonCachedInput = max(0, tokenCount.inputTokens - cachedInput)
            let output = tokenCount.outputTokens

            let cost =
                CostCalculator.cost(
                    model: model,
                    inputTokens: nonCachedInput,
                    outputTokens: output,
                    cacheReadTokens: cachedInput,
                    cache5mTokens: 0,
                    cache1hTokens: 0
                ) ?? 0

            let displayModel = normalizeModel(model)
            dayToCost[sessionKey, default: 0] += cost
            dayToInputTokens[sessionKey, default: 0] += nonCachedInput + cachedInput
            dayToOutputTokens[sessionKey, default: 0] += output
            modelCost[displayModel, default: 0] += cost
            modelTotalTokens[displayModel, default: 0] += nonCachedInput + cachedInput + output
        }

        let chartData = dayToCost.compactMap { key, cost -> DailyUsage? in
            guard let date = dayFormatter.date(from: key) else { return nil }
            return DailyUsage(
                date: date,
                costUSD: cost,
                inputTokens: dayToInputTokens[key] ?? 0,
                outputTokens: dayToOutputTokens[key] ?? 0
            )
        }.sorted { $0.date < $1.date }

        let modelBreakdown = modelCost.map { model, cost in
            ModelUsage(modelName: model, costUSD: cost, totalTokens: modelTotalTokens[model] ?? 0)
        }.sorted { $0.costUSD > $1.costUSD }

        let todayUSD = dayToCost[todayKey] ?? 0
        let thirtyDayUSD = dayToCost.values.reduce(0, +)
        let todayTokens = (dayToInputTokens[todayKey] ?? 0) + (dayToOutputTokens[todayKey] ?? 0)
        let thirtyDayTokens = dayToInputTokens.values.reduce(0, +) + dayToOutputTokens.values.reduce(0, +)

        return AIUsageData(
            cost: CostInfo(
                todayUSD: todayUSD,
                thirtyDayUSD: thirtyDayUSD,
                todayTokens: todayTokens,
                thirtyDayTokens: thirtyDayTokens
            ),
            chartData: chartData,
            modelBreakdown: modelBreakdown,
            planName: "Codex",
            lastUpdated: now
        )
    }

    // Extract date from ~/.codex/sessions/YYYY/MM/DD/ path
    private nonisolated static func dateFromDayDir(_ url: URL) -> Date? {
        let parts = url.pathComponents
        guard parts.count >= 3 else { return nil }
        let year = parts[parts.count - 3]
        let month = parts[parts.count - 2]
        let day = parts[parts.count - 1]
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = .current
        return df.date(from: "\(year)-\(month)-\(day)")
    }

    private nonisolated static func normalizeModel(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("5.4") { return lower.contains("mini") ? "GPT 5.4 mini" : "GPT 5.4" }
        if lower.contains("5.3") && lower.contains("codex") { return "GPT 5.3 Codex" }
        if lower.contains("5.3") { return "GPT 5.3" }
        if lower.contains("gpt-5") { return lower.contains("mini") ? "GPT 5 mini" : "GPT 5" }
        if lower.contains("o4-mini") { return "o4 mini" }
        if lower.contains("o4") { return "o4" }
        if lower.contains("o3-mini") { return "o3 mini" }
        if lower.contains("o3") { return "o3" }
        if lower.contains("gpt-4o") { return lower.contains("mini") ? "GPT-4o mini" : "GPT-4o" }
        if lower.contains("gpt-4") { return "GPT-4" }
        return raw
    }
}

// MARK: - Decodable models (private)

private nonisolated struct CodexEvent: Decodable {
    let type: String
    let payload: CodexEventPayload?
}

private nonisolated struct CodexEventPayload: Decodable {
    let model: String?  // present in turn_context
    let type: String?  // present in event_msg (payload.type)
    let info: CodexTokenInfo?

    enum CodingKeys: String, CodingKey {
        case model, type, info
    }
}

private nonisolated struct CodexTokenInfo: Decodable {
    let totalTokenUsage: CodexTotalUsage?

    enum CodingKeys: String, CodingKey {
        case totalTokenUsage = "total_token_usage"
    }
}

private nonisolated struct CodexTotalUsage: Decodable {
    let inputTokens: Int
    let cachedInputTokens: Int?
    let outputTokens: Int

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case cachedInputTokens = "cached_input_tokens"
        case outputTokens = "output_tokens"
    }
}
