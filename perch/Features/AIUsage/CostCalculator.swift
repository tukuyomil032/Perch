import Foundation

nonisolated enum CostCalculator {
    struct ModelPricing: Sendable {
        let inputPerMillion: Double
        let outputPerMillion: Double
        let cacheReadPerMillion: Double?
    }

    static let pricing: [String: ModelPricing] = [
        "claude-opus-4-6": ModelPricing(inputPerMillion: 15.0, outputPerMillion: 75.0, cacheReadPerMillion: 1.875),
        "claude-opus-4-7": ModelPricing(inputPerMillion: 15.0, outputPerMillion: 75.0, cacheReadPerMillion: 1.875),
        "claude-sonnet-4-6": ModelPricing(inputPerMillion: 3.0, outputPerMillion: 15.0, cacheReadPerMillion: 0.30),
        "claude-haiku-4-5": ModelPricing(inputPerMillion: 0.80, outputPerMillion: 4.0, cacheReadPerMillion: 0.08),
        "gpt-4.1": ModelPricing(inputPerMillion: 2.0, outputPerMillion: 8.0, cacheReadPerMillion: 0.50),
        "o3": ModelPricing(inputPerMillion: 2.0, outputPerMillion: 8.0, cacheReadPerMillion: nil),
        "o4-mini": ModelPricing(inputPerMillion: 1.10, outputPerMillion: 4.40, cacheReadPerMillion: 0.275),
        "gemini-2.5-pro": ModelPricing(inputPerMillion: 1.25, outputPerMillion: 10.0, cacheReadPerMillion: nil),
        "gemini-2.5-flash": ModelPricing(inputPerMillion: 0.15, outputPerMillion: 0.60, cacheReadPerMillion: nil),
    ]

    static func cost(model: String, inputTokens: Int, outputTokens: Int, cacheReadTokens: Int = 0) -> Double? {
        guard let p = pricing[model] else { return nil }
        let inputCost = Double(inputTokens) / 1_000_000 * p.inputPerMillion
        let outputCost = Double(outputTokens) / 1_000_000 * p.outputPerMillion
        let cacheCost =
            cacheReadTokens > 0
            ? Double(cacheReadTokens) / 1_000_000 * (p.cacheReadPerMillion ?? 0)
            : 0.0
        return inputCost + outputCost + cacheCost
    }

    static func estimateCost(totalTokens: Int, model: String) -> Double? {
        let inputTokens = Int(Double(totalTokens) * 0.75)
        let outputTokens = totalTokens - inputTokens
        return cost(model: model, inputTokens: inputTokens, outputTokens: outputTokens)
    }
}
