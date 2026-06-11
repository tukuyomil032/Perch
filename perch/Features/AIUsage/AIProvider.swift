import Foundation

protocol AIProvider: Identifiable, Sendable {
    var id: String { get }
    var displayName: String { get }
    var brandColorHex: String { get }
    var icon: String { get }
    var isConfigured: Bool { get }

    func fetchUsage() async throws -> AIUsageData
}

struct AIUsageData: Sendable {
    var session: UsageTier?
    var weekly: UsageTier?
    var daily: UsageTier?
    var cost: CostInfo?
    var chartData: [DailyUsage]?
    var modelBreakdown: [ModelUsage]?
    var planName: String?
    var lastUpdated: Date?
}

struct UsageTier: Sendable {
    var percentRemaining: Double
    var resetsAt: Date?
    var projectedEmptyAt: Date?
    var label: String
}

struct CostInfo: Sendable {
    var todayUSD: Double
    var thirtyDayUSD: Double
    var todayTokens: Int
    var thirtyDayTokens: Int
}

struct DailyUsage: Sendable, Identifiable {
    var id: Date { date }
    var date: Date
    var costUSD: Double
    var inputTokens: Int
    var outputTokens: Int
}

struct ModelUsage: Sendable, Identifiable {
    var id: String { modelName }
    var modelName: String
    var costUSD: Double
    var totalTokens: Int
}
