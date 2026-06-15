import Defaults
import Foundation

nonisolated struct ClaudeProvider: AIProvider {
    let id = "claude"
    let displayName = "Claude"
    let brandColorHex = "#E8784F"
    let icon = "message.circle.fill"

    nonisolated var isConfigured: Bool {
        Self.loadOAuthAccessToken() != nil || FileManager.default.fileExists(atPath: projectsDir.path)
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
        let dir = projectsDir
        let (sessionLimit, weeklyLimit, dailyLimit) = await MainActor.run {
            (Defaults[.claudeSessionTokenLimit], Defaults[.claudeWeeklyTokenLimit], Defaults[.claudeDailyTokenLimit])
        }

        let localUsage = try await Task.detached(priority: .utility) {
            try Self.parseProjects(
                in: dir,
                sessionLimit: sessionLimit,
                weeklyLimit: weeklyLimit,
                dailyLimit: dailyLimit
            )
        }.value

        guard let accessToken = Self.loadOAuthAccessToken() else {
            return localUsage
        }

        do {
            let liveUsage = try await Self.fetchOAuthUsage(accessToken: accessToken)
            return Self.merging(liveUsage: liveUsage, into: localUsage)
        } catch {
            return localUsage
        }
    }

    // MARK: - Claude OAuth usage API

    private nonisolated static func loadOAuthAccessToken() -> String? {
        let env = ProcessInfo.processInfo.environment
        if let token = env["CLAUDE_OAUTH_TOKEN"]?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            return token
        }
        if let token = env["ANTHROPIC_OAUTH_TOKEN"]?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            return token
        }
        // Claude Code stores OAuth credentials in ~/.claude/.credentials.json
        let credPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
        if let data = try? Data(contentsOf: credPath),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let token = json["access_token"] as? String, !token.isEmpty
        {
            return token
        }
        return KeychainHelper.load(forKey: "claude_oauth_access_token")
    }

    private nonisolated static func fetchOAuthUsage(accessToken: String) async throws -> AIUsageData {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        // Required to avoid aggressive rate-limiting (429)
        req.setValue("claude-code/1.0", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw ClaudeProviderError.httpError((resp as? HTTPURLResponse)?.statusCode ?? 0)
        }

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeProviderError.invalidResponse
        }

        // API returns nested windows: five_hour, seven_day, seven_day_claude_routines
        // utilization = fraction USED (0.0–1.0), stored directly as usedFraction
        func parseTier(_ key: String, label: String) -> UsageTier? {
            guard let window = root[key] as? [String: Any],
                let utilization = doubleValue(in: window, keys: ["utilization"])
            else { return nil }
            let used = min(1.0, max(0.0, utilization))
            let resetsAt = dateValue(in: window, keys: ["resets_at", "resetsAt"])
            return UsageTier(usedFraction: used, resetsAt: resetsAt, label: label, source: .anthropicOAuth)
        }

        return AIUsageData(
            session: parseTier("five_hour", label: "セッション"),
            weekly: parseTier("seven_day", label: "週間"),
            daily: parseTier("seven_day_claude_routines", label: "Daily Routines")
                ?? parseTier("seven_day_routines", label: "Daily Routines")
                ?? routineUsageTier(from: root),
            planName: stringValue(in: root, keys: ["planName", "plan_name"]) ?? "Claude Code",
            lastUpdated: Date()
        )
    }

    private nonisolated static func merging(liveUsage: AIUsageData, into localUsage: AIUsageData) -> AIUsageData {
        var merged = localUsage
        if let session = liveUsage.session { merged.session = session }
        if let weekly = liveUsage.weekly { merged.weekly = weekly }
        if let daily = liveUsage.daily { merged.daily = daily }
        if let planName = liveUsage.planName { merged.planName = planName }
        merged.lastUpdated = liveUsage.lastUpdated ?? Date()
        return merged
    }

    private nonisolated static func routineUsageTier(from root: [String: Any]) -> UsageTier? {
        let preferredKeys = [
            "seven_day_claude_routines", "seven_day_routines", "claude_routines", "routines", "routine",
        ]
        for key in preferredKeys {
            if let tier = routineUsageTier(from: root[key]) {
                return tier
            }
        }
        return firstRoutineUsageTier(in: root)
    }

    private nonisolated static func routineUsageTier(from value: Any?) -> UsageTier? {
        guard let dictionary = value as? [String: Any] else { return nil }
        let utilization = normalizedFraction(
            doubleValue(in: dictionary, keys: ["utilization", "usagePercent", "usage_percent"])
        )
        let usedFraction =
            utilization
            ?? usageFraction(
                used: doubleValue(in: dictionary, keys: ["usage", "current_usage", "currentUsage", "used_credits"]),
                limit: doubleValue(in: dictionary, keys: ["limit", "monthly_limit", "monthlyLimit"])
            )
        guard let usedFraction else { return nil }
        return UsageTier(
            usedFraction: min(1.0, max(0.0, usedFraction)),
            resetsAt: dateValue(in: dictionary, keys: ["resets_at", "resetsAt", "reset_at", "resetAt"]),
            label: "Daily Routines",
            source: .anthropicOAuth
        )
    }

    private nonisolated static func firstRoutineUsageTier(in value: Any) -> UsageTier? {
        if let dictionary = value as? [String: Any] {
            for (key, nested) in dictionary {
                let lower = key.lowercased()
                if lower.contains("routine"), let tier = routineUsageTier(from: nested) {
                    return tier
                }
                if let tier = firstRoutineUsageTier(in: nested) {
                    return tier
                }
            }
        } else if let array = value as? [Any] {
            for nested in array {
                if let tier = firstRoutineUsageTier(in: nested) {
                    return tier
                }
            }
        }
        return nil
    }

    private nonisolated static func doubleValue(in dictionary: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let value = dictionary[key] as? Double { return value }
            if let value = dictionary[key] as? Int { return Double(value) }
            if let value = dictionary[key] as? String, let double = Double(value) { return double }
        }
        return nil
    }

    private nonisolated static func stringValue(in dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String, !value.isEmpty { return value }
        }
        return nil
    }

    private nonisolated static func dateValue(in dictionary: [String: Any], keys: [String]) -> Date? {
        guard let raw = stringValue(in: dictionary, keys: keys) else { return nil }
        return parseAPIDate(raw)
    }

    private nonisolated static func normalizedFraction(_ value: Double?) -> Double? {
        guard let value else { return nil }
        let fraction = value > 1 ? value / 100 : value
        return min(1, max(0, fraction))
    }

    private nonisolated static func usageFraction(used: Double?, limit: Double?) -> Double? {
        guard let used, let limit, limit > 0 else { return nil }
        return min(1, max(0, used / limit))
    }

    private nonisolated static func parseAPIDate(_ raw: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: raw) { return date }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        for format in ["MMM d, h:mma", "MMM d, h:mm a", "MMM d 'at' h:mma", "MMM d 'at' h:mm a"] {
            formatter.dateFormat = format
            if let parsed = formatter.date(from: raw) {
                return Calendar.current.date(
                    bySetting: .year,
                    value: Calendar.current.component(.year, from: Date()),
                    of: parsed
                )
            }
        }
        return nil
    }

    // MARK: - Parsing (off main thread)

    private nonisolated static func parseProjects(
        in dir: URL,
        sessionLimit: Int,
        weeklyLimit: Int,
        dailyLimit: Int
    ) throws -> AIUsageData {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.path) else {
            return AIUsageData(planName: "Claude Code", lastUpdated: Date())
        }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.timeZone = .current

        let decoder = JSONDecoder()
        let now = Date()
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
        let oneHourAgo = Calendar.current.date(byAdding: .hour, value: -1, to: now) ?? now
        let todayKey = dayFormatter.string(from: now)

        // ccusage uses (messageId, requestId) composite key for cross-file dedup
        var seenCompositeKeys = Set<String>()
        var dayToCost: [String: Double] = [:]
        var dayToInputTokens: [String: Int] = [:]
        var dayToOutputTokens: [String: Int] = [:]
        var dayToCacheReadTokens: [String: Int] = [:]
        var dayToCacheCreationTokens: [String: Int] = [:]
        var modelCost: [String: Double] = [:]
        var modelTotalTokens: [String: Int] = [:]
        var sessionTokens = 0  // last 1 hour (session approximation)
        var weekTokens = 0  // last 7 days

        guard
            let enumerator = fm.enumerator(
                at: dir,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        else { return AIUsageData(planName: "Claude Code", lastUpdated: now) }

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jsonl" else { continue }
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

            // Pass 1: within-file dedup — ccusage strategy: keep entry with MOST total tokens
            // when same (messageId, requestId) composite key appears multiple times
            var latestByCompositeKey: [String: (ClaudeEntry, Date)] = [:]
            var entriesWithoutKey: [(ClaudeEntry, Date)] = []

            for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
                let lineData = Data(line.utf8)
                guard let entry = try? decoder.decode(ClaudeEntry.self, from: lineData) else { continue }

                // ccusage: is_valid_usage_entry filters
                guard entry.type == "assistant" else { continue }
                guard entry.isApiErrorMessage != true else { continue }  // skip API error entries
                guard let msg = entry.message else { continue }
                // empty strings are invalid (ccusage checks these)
                if let msgId = msg.id, msgId.isEmpty { continue }
                if let rid = entry.requestId, rid.isEmpty { continue }
                if let model = msg.model, model.isEmpty { continue }

                let date: Date
                if let ts = entry.timestamp, let parsed = isoFormatter.date(from: ts) {
                    date = parsed
                } else {
                    date = now
                }
                guard date >= thirtyDaysAgo else { continue }

                let msgId = msg.id ?? ""
                let rid = entry.requestId ?? ""
                let compositeKey = "\(msgId):\(rid)"

                if !msgId.isEmpty || !rid.isEmpty {
                    // ccusage: keep entry with more total tokens (should_replace_deduped_entry)
                    let newTotal = totalTokens(msg.usage)
                    if let existing = latestByCompositeKey[compositeKey] {
                        let existingTotal = totalTokens(existing.0.message?.usage)
                        if newTotal > existingTotal {
                            latestByCompositeKey[compositeKey] = (entry, date)
                        }
                    } else {
                        latestByCompositeKey[compositeKey] = (entry, date)
                    }
                } else {
                    entriesWithoutKey.append((entry, date))
                }
            }

            // Pass 2: cross-file dedup via composite key set
            let fileCandidates: [(ClaudeEntry, Date)] =
                latestByCompositeKey.compactMap { key, pair in
                    seenCompositeKeys.insert(key).inserted ? pair : nil
                } + entriesWithoutKey

            for (entry, date) in fileCandidates {
                guard let msg = entry.message else { continue }
                let key = dayFormatter.string(from: date)
                let model = normalizeModel(msg.model ?? "unknown")
                let usage = msg.usage

                let inputTokens = usage?.inputTokens ?? 0
                let outputTokens = usage?.outputTokens ?? 0
                let cacheReadTokens = usage?.cacheReadInputTokens ?? 0

                // ccusage: split cache_creation into 5m (1.25x) and 1h (2.0x)
                let cache5mTokens: Int
                let cache1hTokens: Int
                if let breakdown = usage?.cacheCreation {
                    cache5mTokens = breakdown.ephemeral5mInputTokens ?? 0
                    cache1hTokens = breakdown.ephemeral1hInputTokens ?? 0
                } else {
                    // legacy format: all cache_creation treated as 5m
                    cache5mTokens = usage?.cacheCreationInputTokens ?? 0
                    cache1hTokens = 0
                }

                let cost: Double
                if let precomputed = entry.costUSD {
                    cost = precomputed  // costUSD (exact from API) takes priority
                } else if let calculated = CostCalculator.cost(
                    model: msg.model ?? "",
                    inputTokens: inputTokens,
                    outputTokens: outputTokens,
                    cacheReadTokens: cacheReadTokens,
                    cache5mTokens: cache5mTokens,
                    cache1hTokens: cache1hTokens
                ) {
                    cost = calculated
                } else {
                    cost = 0
                }

                let cacheCreationTotal = cache5mTokens + cache1hTokens
                let entryTokens = inputTokens + outputTokens + cacheReadTokens + cacheCreationTotal
                dayToCost[key, default: 0] += cost
                dayToInputTokens[key, default: 0] += inputTokens
                dayToOutputTokens[key, default: 0] += outputTokens
                dayToCacheReadTokens[key, default: 0] += cacheReadTokens
                dayToCacheCreationTokens[key, default: 0] += cacheCreationTotal
                modelCost[model, default: 0] += cost
                modelTotalTokens[model, default: 0] += entryTokens
                if date >= oneHourAgo { sessionTokens += entryTokens }
                if date >= sevenDaysAgo { weekTokens += entryTokens }
            }
        }

        let chartData: [DailyUsage] = dayToCost.compactMap { key, cost -> DailyUsage? in
            guard let date = dayFormatter.date(from: key) else { return nil }
            let input = dayToInputTokens[key] ?? 0
            let output = dayToOutputTokens[key] ?? 0
            return DailyUsage(date: date, costUSD: cost, inputTokens: input, outputTokens: output)
        }.sorted { $0.date < $1.date }

        let modelBreakdown = modelCost.map { model, cost in
            ModelUsage(modelName: model, costUSD: cost, totalTokens: modelTotalTokens[model] ?? 0)
        }.sorted { $0.costUSD > $1.costUSD }

        let todayUSD = dayToCost[todayKey] ?? 0
        let thirtyDayUSD = dayToCost.values.reduce(0, +)
        let todayTokens =
            (dayToInputTokens[todayKey] ?? 0)
            + (dayToOutputTokens[todayKey] ?? 0)
            + (dayToCacheReadTokens[todayKey] ?? 0)
            + (dayToCacheCreationTokens[todayKey] ?? 0)
        let thirtyDayTokens =
            dayToInputTokens.values.reduce(0, +)
            + dayToOutputTokens.values.reduce(0, +)
            + dayToCacheReadTokens.values.reduce(0, +)
            + dayToCacheCreationTokens.values.reduce(0, +)

        // Local estimated usage tiers (shown only when OAuth is unavailable)
        // usedFraction = tokens used / configured limit (unreliable — user-configured limit only)
        let sessionUsed =
            sessionLimit > 0 ? min(1.0, Double(sessionTokens) / Double(sessionLimit)) : 0.0
        let weeklyUsed =
            weeklyLimit > 0 ? min(1.0, Double(weekTokens) / Double(weeklyLimit)) : 0.0
        let dailyUsed =
            dailyLimit > 0 ? min(1.0, Double(todayTokens) / Double(dailyLimit)) : 0.0

        let nextHour = Calendar.current.date(byAdding: .hour, value: 1, to: now)
        let nextWeek = Calendar.current.date(byAdding: .day, value: 7, to: sevenDaysAgo)
        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))

        // Only include estimated tiers when a limit has been configured
        let sessionTier: UsageTier? =
            sessionLimit > 0
            ? UsageTier(usedFraction: sessionUsed, resetsAt: nextHour, label: "セッション", source: .localEstimate)
            : nil
        let weeklyTier: UsageTier? =
            weeklyLimit > 0
            ? UsageTier(usedFraction: weeklyUsed, resetsAt: nextWeek, label: "週間", source: .localEstimate)
            : nil
        let dailyTier: UsageTier? =
            dailyLimit > 0
            ? UsageTier(usedFraction: dailyUsed, resetsAt: nextDay, label: "Daily Routines", source: .localEstimate)
            : nil

        return AIUsageData(
            session: sessionTier,
            weekly: weeklyTier,
            daily: dailyTier,
            cost: CostInfo(
                todayUSD: todayUSD,
                thirtyDayUSD: thirtyDayUSD,
                todayTokens: todayTokens,
                thirtyDayTokens: thirtyDayTokens
            ),
            chartData: chartData,
            modelBreakdown: modelBreakdown,
            planName: "Claude Code",
            lastUpdated: now
        )
    }

    private nonisolated static func totalTokens(_ usage: ClaudeUsage?) -> Int {
        guard let u = usage else { return 0 }
        let cacheCreate: Int
        if let b = u.cacheCreation {
            cacheCreate = (b.ephemeral5mInputTokens ?? 0) + (b.ephemeral1hInputTokens ?? 0)
        } else {
            cacheCreate = u.cacheCreationInputTokens ?? 0
        }
        return (u.inputTokens ?? 0) + (u.outputTokens ?? 0) + cacheCreate + (u.cacheReadInputTokens ?? 0)
    }

    /// Converts raw model IDs to short display names with version numbers.
    private nonisolated static func normalizeModel(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("opus-4-8") { return "Opus 4.8" }
        if lower.contains("opus-4-7") { return "Opus 4.7" }
        if lower.contains("opus-4-6") { return "Opus 4.6" }
        if lower.contains("opus-4") { return "Opus 4" }
        if lower.contains("sonnet-4-6") { return "Sonnet 4.6" }
        if lower.contains("sonnet-4-5") { return "Sonnet 4.5" }
        if lower.contains("sonnet-4") { return "Sonnet 4" }
        if lower.contains("haiku-4-5") { return "Haiku 4.5" }
        if lower.contains("haiku-4") { return "Haiku 4" }
        if lower.contains("opus-3") { return "Opus 3" }
        if lower.contains("sonnet-3-7") { return "Sonnet 3.7" }
        if lower.contains("sonnet-3-5") { return "Sonnet 3.5" }
        if lower.contains("haiku-3") { return "Haiku 3" }
        return raw
    }
}

enum ClaudeProviderError: Error {
    case httpError(Int)
    case invalidResponse
}

// MARK: - Private Decodable models

private nonisolated struct ClaudeEntry: Decodable {
    let type: String
    let isSidechain: Bool?
    let isApiErrorMessage: Bool?
    let timestamp: String?
    let costUSD: Double?  // JSON key: "costUSD" (ccusage uses camelCase)
    let requestId: String?
    let message: ClaudeMessage?

    enum CodingKeys: String, CodingKey {
        case type
        case isSidechain
        case isApiErrorMessage
        case timestamp
        case costUSD  // matches JSON "costUSD" exactly
        case requestId
        case message
    }
}

private nonisolated struct ClaudeMessage: Decodable {
    let id: String?  // for composite dedup key with requestId
    let model: String?
    let usage: ClaudeUsage?
}

private nonisolated struct ClaudeUsage: Decodable {
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheReadInputTokens: Int?
    let cacheCreationInputTokens: Int?
    let cacheCreation: CacheCreationBreakdown?

    nonisolated enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
        case cacheCreation = "cache_creation"
    }
}

private nonisolated struct CacheCreationBreakdown: Decodable {
    let ephemeral5mInputTokens: Int?
    let ephemeral1hInputTokens: Int?

    nonisolated enum CodingKeys: String, CodingKey {
        case ephemeral5mInputTokens = "ephemeral_5m_input_tokens"
        case ephemeral1hInputTokens = "ephemeral_1h_input_tokens"
    }
}
