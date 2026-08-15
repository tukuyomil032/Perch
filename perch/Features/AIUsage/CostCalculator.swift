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

    // Updated: 2026-08-15. Sources: Anthropic pricing docs, CodexBar CostUsagePricing.swift,
    // OpenAI API pricing, Google AI Gemini pricing.
    // Review when providers change their pricing.
    static let pricing: [String: ModelPricing] = [
        // ── Claude (Anthropic) ──────────────────────────────────────────────
        "claude-fable-5": ModelPricing(
            inputPerMillion: 10.0, outputPerMillion: 50.0, cacheReadPerMillion: 1.0, cacheWritePerMillion: 12.50),
        "claude-opus-5": ModelPricing(
            inputPerMillion: 5.0, outputPerMillion: 25.0, cacheReadPerMillion: 0.50, cacheWritePerMillion: 6.25),
        "claude-opus-4-7": ModelPricing(
            inputPerMillion: 5.0, outputPerMillion: 25.0, cacheReadPerMillion: 0.50, cacheWritePerMillion: 6.25),
        "claude-opus-4-8": ModelPricing(
            inputPerMillion: 5.0, outputPerMillion: 25.0, cacheReadPerMillion: 0.50, cacheWritePerMillion: 6.25),
        "claude-opus-4-6": ModelPricing(
            inputPerMillion: 5.0, outputPerMillion: 25.0, cacheReadPerMillion: 0.50, cacheWritePerMillion: 6.25),
        "claude-sonnet-5": ModelPricing(
            inputPerMillion: 2.0, outputPerMillion: 10.0, cacheReadPerMillion: 0.20, cacheWritePermillion: 2.50),
        "claude-sonnet-4-6": ModelPricing(
            inputPerMillion: 3.0, outputPerMillion: 15.0, cacheReadPerMillion: 0.30, cacheWritePerMillion: 3.75),
        "claude-sonnet-4-5": ModelPricing(
            inputPerMillion: 3.0, outputPerMillion: 15.0, cacheReadPerMillion: 0.30, cacheWritePerMillion: 3.75),
        "claude-haiku-4-5": ModelPricing(
            inputPerMillion: 1.0, outputPerMillion: 5.0, cacheReadPerMillion: 0.10, cacheWritePerMillion: 1.25),
        "claude-haiku-4-5-20251001": ModelPricing(
            inputPerMillion: 1.0, outputPerMillion: 5.0, cacheReadPerMillion: 0.10, cacheWritePerMillion: 1.25),
        // ── OpenAI (GPT-5 / Codex) ── Updated 2026-08-15 ───────────────────
        "gpt-5.6-sol": ModelPricing(inputPerMillion: 5.0, outputPerMillion: 30.0, cacheReadPerMillion: 12.50),
        "gpt-5.6-terra": ModelPricing(inputPerMillion: 2.0, outputPerMillion: 12.0, cacheReadPerMillion: 5.0),
        "gpt-5.6-luna": ModelPricing(inputPerMillion: 0.20, outputPerMillion: 1.20, cacheReadPerMillion: 0.50),
        "gpt-5.5": ModelPricing(inputPerMillion: 5.0, outputPerMillion: 30.0, cacheReadPerMillion: 0.50),
        "gpt-5.4": ModelPricing(inputPerMillion: 2.5, outputPerMillion: 15.0, cacheReadPerMillion: 0.25),
        "gpt-5.4-mini": ModelPricing(inputPerMillion: 0.75, outputPerMillion: 4.50, cacheReadPerMillion: 0.075),
        "gpt-5.3-codex": ModelPricing(inputPerMillion: 1.75, outputPerMillion: 14.0, cacheReadPerMillion: 0.175),
        "gpt-5.2": ModelPricing(inputPerMillion: 1.75, outputPerMillion: 14.0, cacheReadPerMillion: 0.175),
        "gpt-5.1-codex-max": ModelPricing(inputPerMillion: 1.25, outputPerMillion: 10.0, cacheReadPerMillion: 0.125),
        "gpt-5.1-codex-mini": ModelPricing(inputPerMillion: 0.25, outputPerMillion: 2.0, cacheReadPerMillion: 0.025),
        "codex-mini": ModelPricing(inputPerMillion: 1.50, outputPerMillion: 6.0, cacheReadPerMillion: nil),
        "gpt-4.1": ModelPricing(inputPerMillion: 2.0, outputPerMillion: 8.0, cacheReadPerMillion: 0.50),
        "gpt-4.1-mini": ModelPricing(inputPerMillion: 0.40, outputPerMillion: 1.60, cacheReadPerMillion: 0.10),
        "o3": ModelPricing(inputPerMillion: 2.0, outputPerMillion: 8.0, cacheReadPerMillion: 0.50),
        "o4-mini": ModelPricing(inputPerMillion: 0.55, outputPerMillion: 2.20, cacheReadPerMillion: nil),
        // ── Google Gemini ────────────────────────────────────────────────────
        "gemini-3.7-flash": ModelPricing(inputPerMillion: 0.75, outputPerMillion: 3.75, cacheReadPerMillion: 0.15),
        "gemini-3.6-flash": ModelPricing(inputPerMillion: 1.50, outputPerMillion: 7.50, cacheReadPerMillion: 0.15),
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
        cacheReadTokens: Int = 0,
        cache5mTokens: Int = 0,  // ephemeral 5-min cache: 1.25× input
        cache1hTokens: Int = 0,  // ephemeral 1-hour cache: 2.0× input (ccusage CACHE_CREATE_1H_INPUT_MULTIPLIER)
        cacheCreationTokens: Int = 0  // legacy field — treated as 5m
    ) -> Double? {
        let lower = model.lowercased()
        guard let p = pricing[lower] ?? resolveFuzzy(lower) else { return nil }
        let inputCost = Double(inputTokens) / 1_000_000 * p.inputPerMillion
        let outputCost = Double(outputTokens) / 1_000_000 * p.outputPerMillion
        let cacheReadCost = Double(cacheReadTokens) / 1_000_000 * (p.cacheReadPerMillion ?? 0)
        let effective5m = cache5mTokens + cacheCreationTokens
        let cache5mCost = Double(effective5m) / 1_000_000 * (p.cacheWritePerMillion ?? p.inputPerMillion * 1.25)
        let cache1hCost = Double(cache1hTokens) / 1_000_000 * (p.inputPerMillion * 2.0)
        return inputCost + outputCost + cacheReadCost + cache5mCost + cache1hCost
    }

    // Handles date-suffixed model IDs like "claude-sonnet-4-5-20250514" → matches "claude-sonnet-4-5"
    private static func resolveFuzzy(_ lower: String) -> ModelPricing? {
        let sorted = pricing.keys.sorted { $0.count > $1.count }
        return sorted.first(where: { lower.hasPrefix($0) }).flatMap { pricing[$0] }
    }

    static func estimateCost(totalTokens count: Int, model: String) -> Double? {
        let inputTokens = Int(Double(count) * 0.75)
        let outputTokens = count - inputTokens
        return cost(model: model, inputTokens: inputTokens, outputTokens: outputTokens)
    }
}
