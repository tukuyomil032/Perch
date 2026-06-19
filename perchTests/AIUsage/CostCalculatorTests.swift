// perchTests/AIUsage/CostCalculatorTests.swift
import Testing

@testable import perch

@Suite("CostCalculator")
@MainActor
struct CostCalculatorTests {
    @Test("unknown model returns nil")
    func unknownModelNil() {
        let result = CostCalculator.cost(model: "gpt-999-ultra", inputTokens: 1000, outputTokens: 500)
        #expect(result == nil)
    }

    @Test("claude-sonnet-4-6 input cost calculated correctly")
    func claudeSonnet46InputCost() {
        // inputPerMillion=3.0: 1_000_000 tokens → $3.00
        let result = CostCalculator.cost(model: "claude-sonnet-4-6", inputTokens: 1_000_000, outputTokens: 0)
        #expect(result != nil)
        #expect(abs(result! - 3.0) < 0.0001)
    }

    @Test("claude-opus-4-6 output cost calculated correctly")
    func claudeOpus46OutputCost() {
        // outputPerMillion=25.0: 1_000_000 tokens → $25.00
        let result = CostCalculator.cost(model: "claude-opus-4-6", inputTokens: 0, outputTokens: 1_000_000)
        #expect(result != nil)
        #expect(abs(result! - 25.0) < 0.0001)
    }

    @Test("cache read cost is included")
    func cacheReadCostIncluded() {
        // claude-sonnet-4-6 cacheReadPerMillion=0.30: 1M cache tokens → $0.30
        let result = CostCalculator.cost(
            model: "claude-sonnet-4-6",
            inputTokens: 0, outputTokens: 0,
            cacheReadTokens: 1_000_000)
        #expect(result != nil)
        #expect(abs(result! - 0.30) < 0.0001)
    }

    @Test("date-suffix model resolves to base model (fuzzy match)")
    func dateSuffixFuzzyMatch() {
        // "claude-haiku-4-5-20251001" should resolve to "claude-haiku-4-5"
        let exact = CostCalculator.cost(model: "claude-haiku-4-5", inputTokens: 1000, outputTokens: 1000)
        let fuzzy = CostCalculator.cost(model: "claude-haiku-4-5-20251001", inputTokens: 1000, outputTokens: 1000)
        #expect(exact != nil)
        #expect(fuzzy != nil)
        #expect(abs(exact! - fuzzy!) < 0.0001)
    }

    @Test("model lookup is case-insensitive")
    func caseInsensitiveLookup() {
        let lower = CostCalculator.cost(model: "claude-sonnet-4-6", inputTokens: 1000, outputTokens: 500)
        let upper = CostCalculator.cost(model: "CLAUDE-SONNET-4-6", inputTokens: 1000, outputTokens: 500)
        #expect(lower != nil)
        #expect(upper != nil)
        #expect(abs(lower! - upper!) < 0.0001)
    }

    @Test("estimateCost uses 75/25 split")
    func estimateCostSplit() {
        // estimateCost splits 1_000_000 tokens as 750_000 input + 250_000 output
        // claude-sonnet-4-6: 750k input @ $3/M + 250k output @ $15/M = $2.25 + $3.75 = $6.00
        let estimate = CostCalculator.estimateCost(totalTokens: 1_000_000, model: "claude-sonnet-4-6")
        #expect(estimate != nil)
        #expect(abs(estimate! - 6.0) < 0.001)
    }

    @Test("zero tokens returns zero cost")
    func zeroCost() {
        let result = CostCalculator.cost(model: "claude-sonnet-4-6", inputTokens: 0, outputTokens: 0)
        #expect(result == 0.0)
    }
}
