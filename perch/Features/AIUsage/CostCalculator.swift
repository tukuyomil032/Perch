import Foundation

nonisolated enum CostCalculator {
    struct ModelPricing: Sendable {
        let inputPerMillion: Double
        let outputPerMillion: Double
        let cacheReadPerMillion: Double?
        let cacheWritePerMillion: Double?

        init(
            inputPerMillion: Double, outputPerMillion: Double, cacheReadPerMillion: Double?,
            cacheWritePerMillion: Double? = nil
        ) {
            self.inputPerMillion = inputPerMillion
            self.outputPerMillion = outputPerMillion
            self.cacheReadPerMillion = cacheReadPerMillion
            self.cacheWritePerMillion = cacheWritePerMillion
        }
    }

    // Updated: 2026-06-12. Sources: Anthropic pricing docs, CodexBar CostUsagePricing.swift,
    // OpenAI API pricing, Google AI Gemini pricing.
    // Review when providers change their pricing.
    static let pricing: [String: ModelPricing] = [
        // ── Claude (Anthropic) ──────────────────────────────────────────────
        "claude-opus-4-6": ModelPricing(
            inputPerMillion: 5.0, outputPerMillion: 25.0, cacheReadPerMillion: 0.50, cacheWritePerMillion: 6.25),
        "claude-opus-4-7": ModelPricing(
            inputPerMillion: 5.0, outputPerMillion: 25.0, cacheReadPerMillion: 0.50, cacheWritePerMillion: 6.25),
        "claude-opus-4-8": ModelPricing(
            inputPerMillion: 5.0, outputPerMillion: 25.0, cacheReadPerMillion: 0.50, cacheWritePerMillion: 6.25),
        "claude-sonnet-4-5": ModelPricing(
            inputPerMillion: 3.0, outputPerMillion: 15.0, cacheReadPerMillion: 0.30, cacheWritePerMillion: 3.75),
        "claude-sonnet-4-6": ModelPricing(
            inputPerMillion: 3.0, outputPerMillion: 15.0, cacheReadPerMillion: 0.30, cacheWritePerMillion: 3.75),
        "claude-haiku-4-5": ModelPricing(
            inputPerMillion: 1.0, outputPerMillion: 5.0, cacheReadPerMillion: 0.10, cacheWritePerMillion: 1.25),
        "claude-haiku-4-5-20251001": ModelPricing(
            inputPerMillion: 1.0, outputPerMillion: 5.0, cacheReadPerMillion: 0.10, cacheWritePerMillion: 1.25),
        // ── OpenAI (GPT-5 / Codex) ──────────────────────────────────────────
        "gpt-5.5": ModelPricing(inputPerMillion: 5.0, outputPerMillion: 30.0, cacheReadPerMillion: 0.50),
        "gpt-5.4": ModelPricing(inputPerMillion: 2.5, outputPerMillion: 15.0, cacheReadPerMillion: nil),
        "gpt-5.3-codex": ModelPricing(inputPerMillion: 1.75, outputPerMillion: 14.0, cacheReadPerMillion: nil),
        "gpt-5.1-codex-max": ModelPricing(inputPerMillion: 1.25, outputPerMillion: 10.0, cacheReadPerMillion: nil),
        "gpt-5.1-codex-mini": ModelPricing(inputPerMillion: 0.25, outputPerMillion: 2.0, cacheReadPerMillion: nil),
        "codex-mini": ModelPricing(inputPerMillion: 1.50, outputPerMillion: 6.0, cacheReadPerMillion: nil),
        "gpt-4.1": ModelPricing(inputPerMillion: 2.0, outputPerMillion: 8.0, cacheReadPerMillion: 0.50),
        "gpt-4.1-mini": ModelPricing(inputPerMillion: 0.40, outputPerMillion: 1.60, cacheReadPerMillion: 0.10),
        "o3": ModelPricing(inputPerMillion: 2.0, outputPerMillion: 8.0, cacheReadPerMillion: nil),
        "o4-mini": ModelPricing(inputPerMillion: 0.55, outputPerMillion: 2.20, cacheReadPerMillion: nil),
        // ── Google Gemini ────────────────────────────────────────────────────
        "gemini-3.5-flash": ModelPricing(inputPerMillion: 1.50, outputPerMillion: 9.0, cacheReadPerMillion: 0.15),
        "gemini-3.1-pro-preview": ModelPricing(inputPerMillion: 2.0, outputPerMillion: 12.0, cacheReadPerMillion: 0.20),
        "gemini-3.1-flash-lite-preview": ModelPricing(
            inputPerMillion: 0.25, outputPerMillion: 1.50, cacheReadPerMillion: nil),
        "gemini-3-flash-preview": ModelPricing(inputPerMillion: 0.50, outputPerMillion: 3.0, cacheReadPerMillion: nil),
        "gemini-2.5-pro": ModelPricing(inputPerMillion: 1.25, outputPerMillion: 10.0, cacheReadPerMillion: 0.125),
        "gemini-2.5-flash": ModelPricing(inputPerMillion: 0.30, outputPerMillion: 2.50, cacheReadPerMillion: 0.03),
        "gemini-2.5-flash-lite": ModelPricing(inputPerMillion: 0.10, outputPerMillion: 0.40, cacheReadPerMillion: nil),
    ]

    static func cost(
        model: String, inputTokens: Int, outputTokens: Int,
        cacheReadTokens: Int = 0, cacheCreationTokens: Int = 0
    ) -> Double? {
        let lower = model.lowercased()
        guard let p = pricing[lower] ?? resolveFuzzy(lower) else { return nil }
        let inputCost = Double(inputTokens) / 1_000_000 * p.inputPerMillion
        let outputCost = Double(outputTokens) / 1_000_000 * p.outputPerMillion
        let cacheReadCost = Double(cacheReadTokens) / 1_000_000 * (p.cacheReadPerMillion ?? 0)
        let cacheWriteCost =
            Double(cacheCreationTokens) / 1_000_000 * (p.cacheWritePerMillion ?? p.inputPerMillion * 1.25)
        return inputCost + outputCost + cacheReadCost + cacheWriteCost
    }

    // Handles date-suffixed model IDs like "claude-sonnet-4-5-20250514" → matches "claude-sonnet-4-5"
    private static func resolveFuzzy(_ lower: String) -> ModelPricing? {
        let sorted = pricing.keys.sorted { $0.count > $1.count }
        return sorted.first(where: { lower.hasPrefix($0) }).flatMap { pricing[$0] }
    }

    static func estimateCost(totalTokens: Int, model: String) -> Double? {
        let inputTokens = Int(Double(totalTokens) * 0.75)
        let outputTokens = totalTokens - inputTokens
        return cost(model: model, inputTokens: inputTokens, outputTokens: outputTokens)
    }
}
