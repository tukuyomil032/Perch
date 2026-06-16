import Foundation

// OpenAI official Usage API (announced Dec 2024).
// Requires Organization Admin API Key — NOT a regular sk-... project key.
// Admin keys are created at: platform.openai.com/settings/organization/admin-keys
nonisolated struct OpenAIProvider: AIProvider {
    let id = "openai"
    let displayName = "OpenAI"
    let brandColorHex = "#10A37F"
    let icon = "sparkles"

    static let keychainKey = "openai_admin_key"

    nonisolated var isConfigured: Bool {
        KeychainHelper.load(forKey: Self.keychainKey) != nil
    }

    static func saveAPIKey(_ key: String) throws {
        try KeychainHelper.save(key, forKey: keychainKey)
    }

    static func deleteAPIKey() {
        KeychainHelper.delete(forKey: keychainKey)
    }

    nonisolated func fetchUsage() async throws -> AIUsageData {
        guard let apiKey = KeychainHelper.load(forKey: Self.keychainKey) else {
            return AIUsageData(planName: "OpenAI", lastUpdated: Date())
        }

        let now = Date()
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
        let startTime = Int(thirtyDaysAgo.timeIntervalSince1970)
        let endTime = Int(now.timeIntervalSince1970)

        // Fetch costs and token usage in parallel
        async let costsResult = fetchCosts(apiKey: apiKey, start: startTime, end: endTime)
        async let usageResult = fetchCompletionsUsage(apiKey: apiKey, start: startTime, end: endTime)
        let (costs, usage) = try await (costsResult, usageResult)

        return buildUsageData(costs: costs, usage: usage, now: now)
    }

    // MARK: - API calls

    private nonisolated func fetchCosts(apiKey: String, start: Int, end: Int) async throws -> OpenAICostPage {
        var comps = URLComponents(string: "https://api.openai.com/v1/organization/costs")!
        comps.queryItems = [
            URLQueryItem(name: "start_time", value: "\(start)"),
            URLQueryItem(name: "end_time", value: "\(end)"),
            URLQueryItem(name: "bucket_width", value: "1d"),
            URLQueryItem(name: "limit", value: "30"),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw OpenAIProviderError.httpError((resp as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try JSONDecoder().decode(OpenAICostPage.self, from: data)
    }

    private nonisolated func fetchCompletionsUsage(apiKey: String, start: Int, end: Int) async throws -> OpenAIUsagePage
    {
        var comps = URLComponents(string: "https://api.openai.com/v1/organization/usage/completions")!
        comps.queryItems = [
            URLQueryItem(name: "start_time", value: "\(start)"),
            URLQueryItem(name: "end_time", value: "\(end)"),
            URLQueryItem(name: "bucket_width", value: "1d"),
            URLQueryItem(name: "limit", value: "30"),
            URLQueryItem(name: "group_by[]", value: "model"),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw OpenAIProviderError.httpError((resp as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try JSONDecoder().decode(OpenAIUsagePage.self, from: data)
    }

    // MARK: - Data assembly

    private nonisolated func buildUsageData(costs: OpenAICostPage, usage: OpenAIUsagePage, now: Date) -> AIUsageData {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = .current
        let todayKey = df.string(from: now)

        var dayToCost: [String: Double] = [:]
        var dayToInput: [String: Int] = [:]
        var dayToOutput: [String: Int] = [:]
        var modelTokens: [String: Int] = [:]

        for bucket in costs.data {
            let key = df.string(from: Date(timeIntervalSince1970: TimeInterval(bucket.startTime)))
            let total = bucket.results.reduce(0.0) { $0 + ($1.amount?.value ?? 0) }
            dayToCost[key, default: 0] += total
        }

        for bucket in usage.data {
            let key = df.string(from: Date(timeIntervalSince1970: TimeInterval(bucket.startTime)))
            for result in bucket.results {
                let input = result.inputTokens ?? 0
                let output = result.outputTokens ?? 0
                let model = result.model ?? "unknown"
                dayToInput[key, default: 0] += input
                dayToOutput[key, default: 0] += output
                modelTokens[model, default: 0] += input + output
            }
        }

        // Allocate total cost proportionally to model token share
        let totalTok = modelTokens.values.reduce(0, +)
        let totalCost = dayToCost.values.reduce(0, +)
        let modelCost: [String: Double] =
            totalTok > 0
            ? Dictionary(
                uniqueKeysWithValues: modelTokens.map { m, t in
                    (m, totalCost * Double(t) / Double(totalTok))
                })
            : [:]

        let chartData = dayToCost.compactMap { key, cost -> DailyUsage? in
            guard let date = df.date(from: key) else { return nil }
            return DailyUsage(
                date: date, costUSD: cost, inputTokens: dayToInput[key] ?? 0, outputTokens: dayToOutput[key] ?? 0)
        }.sorted { $0.date < $1.date }

        let modelBreakdown = modelCost.map { model, cost in
            ModelUsage(modelName: model, costUSD: cost, totalTokens: modelTokens[model] ?? 0)
        }.sorted { $0.costUSD > $1.costUSD }

        let todayUSD = dayToCost[todayKey] ?? 0
        let thirtyDayUSD = totalCost
        let todayTokens = (dayToInput[todayKey] ?? 0) + (dayToOutput[todayKey] ?? 0)
        let thirtyDayTokens = dayToInput.values.reduce(0, +) + dayToOutput.values.reduce(0, +)

        return AIUsageData(
            cost: CostInfo(
                todayUSD: todayUSD, thirtyDayUSD: thirtyDayUSD, todayTokens: todayTokens,
                thirtyDayTokens: thirtyDayTokens),
            chartData: chartData,
            modelBreakdown: modelBreakdown,
            planName: "OpenAI",
            lastUpdated: now
        )
    }
}

// MARK: - Errors

enum OpenAIProviderError: Error {
    case httpError(Int)
}

// MARK: - Response models

private nonisolated struct OpenAICostPage: Decodable {
    let data: [CostBucket]

    struct CostBucket: Decodable {
        let startTime: Int
        let results: [CostResult]

        enum CodingKeys: String, CodingKey {
            case startTime = "start_time"
            case results
        }

        struct CostResult: Decodable {
            let amount: Amount?
            let lineItem: String?

            enum CodingKeys: String, CodingKey {
                case amount
                case lineItem = "line_item"
            }

            // amount.value is occasionally returned as a String by the API (CodexBar finding)
            struct Amount: Decodable {
                let value: Double

                init(from decoder: Decoder) throws {
                    let c = try decoder.container(keyedBy: CodingKeys.self)
                    if let d = try? c.decode(Double.self, forKey: .value) {
                        value = d
                    } else if let s = try? c.decode(String.self, forKey: .value), let d = Double(s) {
                        value = d
                    } else {
                        value = 0
                    }
                }

                enum CodingKeys: String, CodingKey { case value }
            }
        }
    }
}

private nonisolated struct OpenAIUsagePage: Decodable {
    let data: [UsageBucket]

    struct UsageBucket: Decodable {
        let startTime: Int
        let results: [UsageResult]

        enum CodingKeys: String, CodingKey {
            case startTime = "start_time"
            case results
        }

        struct UsageResult: Decodable {
            let model: String?
            let inputTokens: Int?
            let outputTokens: Int?

            enum CodingKeys: String, CodingKey {
                case model
                case inputTokens = "input_tokens"
                case outputTokens = "output_tokens"
            }
        }
    }
}
