import Foundation

// MARK: - Parser

nonisolated enum ClaudeLocalUsageParser {
    static func parseUsage(in dir: URL) throws -> ClaudeLocalUsage {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.path) else {
            return ClaudeLocalUsage(
                todayTokens: 0, thirtyDayTokens: 0,
                todayCostUSD: 0, thirtyDayCostUSD: 0,
                dailyUsage: [], modelBreakdown: []
            )
        }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.timeZone = .current

        let decoder = JSONDecoder()
        let now = Date()
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
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

        guard
            let enumerator = fm.enumerator(
                at: dir,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return ClaudeLocalUsage(
                todayTokens: 0, thirtyDayTokens: 0,
                todayCostUSD: 0, thirtyDayCostUSD: 0,
                dailyUsage: [], modelBreakdown: []
            )
        }

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jsonl" else { continue }
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

            // Pass 1: within-file dedup — ccusage: keep entry with MOST total tokens
            var latestByCompositeKey: [String: (LocalClaudeEntry, Date)] = [:]
            var entriesWithoutKey: [(LocalClaudeEntry, Date)] = []

            for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
                let lineData = Data(line.utf8)
                guard let entry = try? decoder.decode(LocalClaudeEntry.self, from: lineData) else { continue }

                guard entry.type == "assistant" else { continue }
                guard entry.isApiErrorMessage != true else { continue }
                guard let msg = entry.message else { continue }
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
                    let newTotal = totalTokens(msg.usage)
                    if let existing = latestByCompositeKey[compositeKey] {
                        if newTotal > totalTokens(existing.0.message?.usage) {
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
            let fileCandidates: [(LocalClaudeEntry, Date)] =
                latestByCompositeKey.compactMap { key, pair in
                    seenCompositeKeys.insert(key).inserted ? pair : nil
                } + entriesWithoutKey

            for (entry, date) in fileCandidates {
                guard let msg = entry.message else { continue }
                let dayKey = dayFormatter.string(from: date)
                let model = normalizeModel(msg.model ?? "unknown")
                let usage = msg.usage

                let inputTokens = usage?.inputTokens ?? 0
                let outputTokens = usage?.outputTokens ?? 0
                let cacheReadTokens = usage?.cacheReadInputTokens ?? 0

                let cache5mTokens: Int
                let cache1hTokens: Int
                if let breakdown = usage?.cacheCreation {
                    cache5mTokens = breakdown.ephemeral5mInputTokens ?? 0
                    cache1hTokens = breakdown.ephemeral1hInputTokens ?? 0
                } else {
                    cache5mTokens = usage?.cacheCreationInputTokens ?? 0
                    cache1hTokens = 0
                }

                let cost: Double
                if let precomputed = entry.costUSD {
                    cost = precomputed
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
                dayToCost[dayKey, default: 0] += cost
                dayToInputTokens[dayKey, default: 0] += inputTokens
                dayToOutputTokens[dayKey, default: 0] += outputTokens
                dayToCacheReadTokens[dayKey, default: 0] += cacheReadTokens
                dayToCacheCreationTokens[dayKey, default: 0] += cacheCreationTotal
                modelCost[model, default: 0] += cost
                modelTotalTokens[model, default: 0] += entryTokens
            }
        }

        let chartData: [DailyUsage] = dayToCost.compactMap { key, cost -> DailyUsage? in
            guard let date = dayFormatter.date(from: key) else { return nil }
            return DailyUsage(
                date: date, costUSD: cost,
                inputTokens: dayToInputTokens[key] ?? 0,
                outputTokens: dayToOutputTokens[key] ?? 0
            )
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

        return ClaudeLocalUsage(
            todayTokens: todayTokens,
            thirtyDayTokens: thirtyDayTokens,
            todayCostUSD: todayUSD,
            thirtyDayCostUSD: thirtyDayUSD,
            dailyUsage: chartData,
            modelBreakdown: modelBreakdown
        )
    }

    private static func totalTokens(_ usage: LocalClaudeUsage?) -> Int {
        guard let u = usage else { return 0 }
        let cacheCreate: Int
        if let b = u.cacheCreation {
            cacheCreate = (b.ephemeral5mInputTokens ?? 0) + (b.ephemeral1hInputTokens ?? 0)
        } else {
            cacheCreate = u.cacheCreationInputTokens ?? 0
        }
        return (u.inputTokens ?? 0) + (u.outputTokens ?? 0) + cacheCreate + (u.cacheReadInputTokens ?? 0)
    }

    private static func normalizeModel(_ raw: String) -> String {
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

// MARK: - Private JSONL Decodable models (prefixed to avoid name collisions)

private nonisolated struct LocalClaudeEntry: Decodable {
    let type: String
    let isSidechain: Bool?
    let isApiErrorMessage: Bool?
    let timestamp: String?
    let costUSD: Double?
    let requestId: String?
    let message: LocalClaudeMessage?
}

private nonisolated struct LocalClaudeMessage: Decodable {
    let id: String?
    let model: String?
    let usage: LocalClaudeUsage?
}

private nonisolated struct LocalClaudeUsage: Decodable {
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheReadInputTokens: Int?
    let cacheCreationInputTokens: Int?
    let cacheCreation: LocalCacheCreationBreakdown?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
        case cacheCreation = "cache_creation"
    }
}

private nonisolated struct LocalCacheCreationBreakdown: Decodable {
    let ephemeral5mInputTokens: Int?
    let ephemeral1hInputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case ephemeral5mInputTokens = "ephemeral_5m_input_tokens"
        case ephemeral1hInputTokens = "ephemeral_1h_input_tokens"
    }
}
