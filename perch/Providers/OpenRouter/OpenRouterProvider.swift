import Foundation

// OpenRouter supports two API key tiers:
// - Regular API Key (sk-or-v1-...): /api/v1/key gives daily/weekly/monthly totals
// - Management API Key: /api/v1/activity gives 30-day daily + model breakdown (chart-ready)
// Both keys are stored separately. If management key is present, full chart data is shown.
nonisolated struct OpenRouterProvider: AIProvider {
    let id = "openrouter"
    let displayName = "OpenRouter"
    let brandColorHex = "#6467F2"
    let icon = "arrow.triangle.branch"

    static let regularKeychainKey = "openrouter_api_key"
    static let managementKeychainKey = "openrouter_mgmt_key"

    nonisolated var isConfigured: Bool {
        KeychainHelper.load(forKey: Self.regularKeychainKey) != nil
            || KeychainHelper.load(forKey: Self.managementKeychainKey) != nil
    }

    static func saveRegularKey(_ key: String) throws {
        try KeychainHelper.save(key, forKey: regularKeychainKey)
    }

    static func saveManagementKey(_ key: String) throws {
        try KeychainHelper.save(key, forKey: managementKeychainKey)
    }

    static func deleteRegularKey() { KeychainHelper.delete(forKey: regularKeychainKey) }
    static func deleteManagementKey() { KeychainHelper.delete(forKey: managementKeychainKey) }

    nonisolated func fetchUsage() async throws -> AIUsageData {
        if let mgmtKey = KeychainHelper.load(forKey: Self.managementKeychainKey) {
            return try await fetchActivity(apiKey: mgmtKey)
        } else if let regularKey = KeychainHelper.load(forKey: Self.regularKeychainKey) {
            return try await fetchKeyInfo(apiKey: regularKey)
        }
        return AIUsageData(planName: "OpenRouter", lastUpdated: Date())
    }

    // MARK: - Management Key path: /api/v1/activity (30-day daily + model breakdown)

    private nonisolated func fetchActivity(apiKey: String) async throws -> AIUsageData {
        var req = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/activity")!)
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw OpenRouterProviderError.httpError((resp as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let response = try JSONDecoder().decode(OpenRouterActivityResponse.self, from: data)
        return response.toAIUsageData()
    }

    // MARK: - Regular Key path: /api/v1/key (today/weekly/monthly totals only, no chart)

    private nonisolated func fetchKeyInfo(apiKey: String) async throws -> AIUsageData {
        var req = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/key")!)
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw OpenRouterProviderError.httpError((resp as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let response = try JSONDecoder().decode(OpenRouterKeyResponse.self, from: data)
        return response.toAIUsageData()
    }
}

// MARK: - Errors

enum OpenRouterProviderError: Error {
    case httpError(Int)
}

// MARK: - Activity response (Management Key)

private nonisolated struct OpenRouterActivityResponse: Decodable {
    let data: [Entry]?

    struct Entry: Decodable {
        let date: String
        let model: String?
        let usage: Double?
        let promptTokens: Int?
        let completionTokens: Int?

        enum CodingKeys: String, CodingKey {
            case date, model, usage
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
        }
    }

    func toAIUsageData() -> AIUsageData {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = .current
        let todayKey = df.string(from: Date())

        var dayToCost: [String: Double] = [:]
        var dayToInput: [String: Int] = [:]
        var dayToOutput: [String: Int] = [:]
        var modelCost: [String: Double] = [:]
        var modelTokens: [String: Int] = [:]

        for entry in data ?? [] {
            let cost = entry.usage ?? 0
            let input = entry.promptTokens ?? 0
            let output = entry.completionTokens ?? 0
            let model = entry.model ?? "unknown"

            dayToCost[entry.date, default: 0] += cost
            dayToInput[entry.date, default: 0] += input
            dayToOutput[entry.date, default: 0] += output
            modelCost[model, default: 0] += cost
            modelTokens[model, default: 0] += input + output
        }

        let chartData = dayToCost.compactMap { key, cost -> DailyUsage? in
            guard let date = df.date(from: key) else { return nil }
            return DailyUsage(
                date: date, costUSD: cost, inputTokens: dayToInput[key] ?? 0, outputTokens: dayToOutput[key] ?? 0)
        }.sorted { $0.date < $1.date }

        let modelBreakdown = modelCost.map { model, cost in
            ModelUsage(modelName: model, costUSD: cost, totalTokens: modelTokens[model] ?? 0)
        }.sorted { $0.costUSD > $1.costUSD }

        let todayUSD = dayToCost[todayKey] ?? 0
        let thirtyDayUSD = dayToCost.values.reduce(0, +)
        let todayTokens = (dayToInput[todayKey] ?? 0) + (dayToOutput[todayKey] ?? 0)
        let thirtyDayTokens = dayToInput.values.reduce(0, +) + dayToOutput.values.reduce(0, +)

        return AIUsageData(
            cost: CostInfo(
                todayUSD: todayUSD, thirtyDayUSD: thirtyDayUSD, todayTokens: todayTokens,
                thirtyDayTokens: thirtyDayTokens),
            chartData: chartData,
            modelBreakdown: modelBreakdown,
            planName: "OpenRouter",
            lastUpdated: Date()
        )
    }
}

// MARK: - Key info response (Regular Key)

private nonisolated struct OpenRouterKeyResponse: Decodable {
    let data: KeyData?

    struct KeyData: Decodable {
        let usage: Double?
        let usageDaily: Double?
        let usageWeekly: Double?
        let usageMonthly: Double?

        enum CodingKeys: String, CodingKey {
            case usage
            case usageDaily = "usage_daily"
            case usageWeekly = "usage_weekly"
            case usageMonthly = "usage_monthly"
        }
    }

    func toAIUsageData() -> AIUsageData {
        guard let d = data else {
            return AIUsageData(planName: "OpenRouter", lastUpdated: Date())
        }
        let todayUSD = d.usageDaily ?? 0
        let thirtyDayUSD = d.usage ?? 0
        let today = Date()
        let todayEntry = DailyUsage(date: today, costUSD: todayUSD, inputTokens: 0, outputTokens: 0)

        return AIUsageData(
            cost: CostInfo(todayUSD: todayUSD, thirtyDayUSD: thirtyDayUSD, todayTokens: 0, thirtyDayTokens: 0),
            chartData: [todayEntry],
            modelBreakdown: [],
            planName: "OpenRouter",
            lastUpdated: today
        )
    }
}
