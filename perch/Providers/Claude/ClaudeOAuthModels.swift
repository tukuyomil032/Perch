import Foundation

// MARK: - API response models (typed Decodable — no [String: Any] in production)

nonisolated struct ClaudeOAuthUsageResponse: Decodable, Sendable {
    let fiveHour: ClaudeUsageBucket?
    let sevenDay: ClaudeUsageBucket?
    let sevenDayRoutines: ClaudeUsageBucket?
    let planName: String?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayRoutines = "seven_day_claude_routines"
        case planName = "plan_name"
    }
}

nonisolated struct ClaudeUsageBucket: Decodable, Sendable {
    let utilization: Double
    let resetsAt: Date?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

// MARK: - Intermediate domain models

nonisolated struct ClaudeLimitUsage: Sendable {
    let session: UsageWindow?
    let weekly: UsageWindow?
    let routines: UsageWindow?
    let planName: String?
}

nonisolated struct UsageWindow: Sendable {
    let usedFraction: Double  // 0.0–1.0
    let resetsAt: Date?
}

// MARK: - Local JSONL statistics

nonisolated struct ClaudeLocalUsage: Sendable {
    let todayTokens: Int
    let thirtyDayTokens: Int
    let todayCostUSD: Double
    let thirtyDayCostUSD: Double
    let dailyUsage: [DailyUsage]
    let modelBreakdown: [ModelUsage]
}
