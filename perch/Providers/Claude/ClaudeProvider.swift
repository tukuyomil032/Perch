import Foundation

nonisolated struct ClaudeProvider: AIProvider {
    let id = "claude"
    let displayName = "Claude"
    let brandColorHex = "#E8784F"
    let icon = "message.circle.fill"

    nonisolated var isConfigured: Bool {
        FileManager.default.fileExists(atPath: projectsDir.path)
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
        return try await Task.detached(priority: .utility) {
            try Self.parseProjects(in: dir)
        }.value
    }

    // MARK: - Parsing (off main thread)

    private nonisolated static func parseProjects(in dir: URL) throws -> AIUsageData {
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
        let todayKey = dayFormatter.string(from: now)

        var dayToCost: [String: Double] = [:]
        var dayToInputTokens: [String: Int] = [:]
        var dayToOutputTokens: [String: Int] = [:]
        var modelCost: [String: Double] = [:]
        var modelTotalTokens: [String: Int] = [:]

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

            for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
                let lineData = Data(line.utf8)
                guard let entry = try? decoder.decode(ClaudeEntry.self, from: lineData),
                    entry.type == "assistant",
                    let msg = entry.message
                else { continue }

                let date: Date
                if let ts = entry.timestamp,
                    let parsed = isoFormatter.date(from: ts)
                {
                    date = parsed
                } else {
                    date = now
                }
                guard date >= thirtyDaysAgo else { continue }

                let key = dayFormatter.string(from: date)
                let model = normalizeModel(msg.model ?? "unknown")
                let usage = msg.usage

                let inputTokens = usage?.inputTokens ?? 0
                let outputTokens = usage?.outputTokens ?? 0
                let cacheReadTokens = usage?.cacheReadInputTokens ?? 0

                let cost: Double
                if let precomputed = entry.costUSD {
                    cost = precomputed
                } else if let calculated = CostCalculator.cost(
                    model: msg.model ?? "",
                    inputTokens: inputTokens,
                    outputTokens: outputTokens,
                    cacheReadTokens: cacheReadTokens
                ) {
                    cost = calculated
                } else {
                    cost = 0
                }

                dayToCost[key, default: 0] += cost
                dayToInputTokens[key, default: 0] += inputTokens
                dayToOutputTokens[key, default: 0] += outputTokens
                modelCost[model, default: 0] += cost
                modelTotalTokens[model, default: 0] += inputTokens + outputTokens
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
            planName: "Claude Code",
            lastUpdated: now
        )
    }

    /// Converts raw model IDs to short display names.
    private nonisolated static func normalizeModel(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("opus-4") { return "Opus 4" }
        if lower.contains("sonnet-4") { return "Sonnet 4" }
        if lower.contains("haiku-4") { return "Haiku 4" }
        if lower.contains("opus-3") { return "Opus 3" }
        if lower.contains("sonnet-3-7") { return "Sonnet 3.7" }
        if lower.contains("sonnet-3-5") { return "Sonnet 3.5" }
        if lower.contains("haiku-3") { return "Haiku 3" }
        return raw
    }
}

// MARK: - Private Decodable models

private nonisolated struct ClaudeEntry: Decodable {
    let type: String
    let timestamp: String?
    let costUSD: Double?
    let message: ClaudeMessage?
}

private nonisolated struct ClaudeMessage: Decodable {
    let model: String?
    let usage: ClaudeUsage?
}

private nonisolated struct ClaudeUsage: Decodable {
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheReadInputTokens: Int?

    nonisolated enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
    }
}
