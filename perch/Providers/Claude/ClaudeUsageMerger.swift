import Foundation

nonisolated enum ClaudeUsageMerger {
    static func merge(
        remote: Result<ClaudeLimitUsage, ClaudeProviderError>,
        local: Result<ClaudeLocalUsage, ClaudeProviderError>
    ) -> AIUsageData {
        switch (remote, local) {
        case (.success(let limits), .success(let localUsage)):
            return makeData(limits: limits, local: localUsage, warning: nil)

        case (.success(let limits), .failure(let localErr)):
            return makeData(
                limits: limits, local: nil,
                warning: "ローカルログ読み取り失敗: \(localErr.localizedDescription ?? "")"
            )

        case (.failure(let remoteErr), .success(let localUsage)):
            return makeData(
                limits: nil, local: localUsage,
                warning: "公式使用量取得失敗: \(remoteErr.errorDescription ?? remoteErr.localizedDescription)"
            )

        case (.failure(let remoteErr), .failure(let localErr)):
            var data = AIUsageData()
            data.planName = "Claude Code"
            data.lastUpdated = Date()
            data.warningMessage =
                "\(remoteErr.errorDescription ?? "") \(localErr.errorDescription ?? "")"
                .trimmingCharacters(in: .whitespaces)
            return data
        }
    }

    private static func makeData(
        limits: ClaudeLimitUsage?,
        local: ClaudeLocalUsage?,
        warning: String?
    ) -> AIUsageData {
        let session = limits?.session.map { window in
            UsageTier(
                usedFraction: window.usedFraction, resetsAt: window.resetsAt,
                label: "セッション", source: .anthropicOAuth,
                periodDuration: 5 * 3600)
        }
        let weekly = limits?.weekly.map { window in
            UsageTier(
                usedFraction: window.usedFraction, resetsAt: window.resetsAt,
                label: "週間", source: .anthropicOAuth,
                periodDuration: 7 * 24 * 3600)
        }
        let routines = limits?.routines.map { window in
            UsageTier(
                usedFraction: window.usedFraction, resetsAt: window.resetsAt,
                label: "Daily Routines", source: .anthropicOAuth,
                periodDuration: 7 * 24 * 3600)
        }

        let cost = local.map { l in
            CostInfo(
                todayUSD: l.todayCostUSD,
                thirtyDayUSD: l.thirtyDayCostUSD,
                todayTokens: l.todayTokens,
                thirtyDayTokens: l.thirtyDayTokens
            )
        }

        var data = AIUsageData()
        data.session = session
        data.weekly = weekly
        data.daily = routines
        data.cost = cost
        data.chartData = local?.dailyUsage
        data.modelBreakdown = local?.modelBreakdown
        data.planName = limits?.planName ?? "Claude Code"
        data.lastUpdated = Date()
        data.warningMessage = warning
        return data
    }
}
