import SwiftUI

// MARK: - PerchWidget Conformance

nonisolated struct AIUsageWidget: PerchWidget {
    nonisolated let id = "ai-usage"
    nonisolated let displayName = "AI Usage"
    nonisolated let icon = "sparkles"
    nonisolated let supportedSizes: Set<WidgetSize> = [.mini, .compact, .standard, .full]

    @MainActor func body(size: WidgetSize) -> AnyView {
        switch size {
        case .mini: AnyView(AIUsageMiniView())
        case .compact: AnyView(AIUsageCompactView())
        case .standard: AnyView(AIUsageStandardView())
        case .full: AnyView(AIUsageFullView())
        }
    }
}

// MARK: - Mini (tiny indicator, used in dual-activity pill or side slots)

struct AIUsageMiniView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let store = appState.aiUsageStore
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2)
                .fill(DesignSystem.claudeAmber)
                .frame(width: 8, height: 8)
            Text("Claude")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            if let cost = store.activeUsage?.cost {
                Text(formatCost(cost.todayUSD))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
            } else {
                Text(store.isRefreshing ? "···" : "—")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Compact (one-liner for Daily preset bottom bar)

struct AIUsageCompactView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let store = appState.aiUsageStore
        let usage = store.activeUsage

        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(DesignSystem.claudeAmber)
                .frame(width: 8, height: 8)
            Text("Claude Code")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if store.isRefreshing {
                ProgressView().scaleEffect(0.45)
            } else if let cost = usage?.cost {
                HStack(spacing: 6) {
                    Text(formatCost(cost.todayUSD))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)
                    Text("today")
                        .font(.system(size: 9))
                        .foregroundStyle(.quaternary)
                }
            } else if let err = store.errors["claude"] {
                Label(err, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("—")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Standard (cost + chart + model list — used in Dev preset main area)

struct AIUsageStandardView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let store = appState.aiUsageStore
        let usage = store.activeUsage
        let chartData = Array((usage?.chartData ?? []).suffix(14))

        VStack(alignment: .leading, spacing: 0) {
            // Provider header
            HStack {
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(DesignSystem.claudeAmber)
                        .frame(width: 7, height: 7)
                    Text("Claude Code")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if store.isRefreshing {
                    ProgressView().scaleEffect(0.45)
                } else {
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 10)

            // Cost 2-column
            HStack(alignment: .top, spacing: 0) {
                costColumn(
                    label: "Today",
                    amount: usage?.cost.map { formatCost($0.todayUSD) } ?? "—",
                    tokens: usage?.cost.map { formatTokens($0.todayTokens) }
                )
                Spacer()
                costColumn(
                    label: "30 days",
                    amount: usage?.cost.map { formatCost($0.thirtyDayUSD) } ?? "—",
                    tokens: usage?.cost.map { formatTokens($0.thirtyDayTokens) }
                )
            }

            Spacer(minLength: 10)

            // Bar chart
            if !chartData.isEmpty {
                MiniBarChart(data: chartData)
                if let top = usage?.modelBreakdown?.first {
                    Text("Top model: \(top.modelName) · Est. from local logs")
                        .font(.system(size: 9))
                        .foregroundStyle(.quaternary)
                        .padding(.top, 4)
                }
            }

            // Model list
            if let models = usage?.modelBreakdown, !models.isEmpty {
                Divider()
                    .opacity(0.15)
                    .padding(.vertical, 8)
                VStack(spacing: 5) {
                    ForEach(models.prefix(3)) { model in
                        HStack(spacing: 8) {
                            Text(model.modelName)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer()
                            Text(formatTokens(model.totalTokens))
                                .font(.system(size: 9))
                                .foregroundStyle(.quaternary)
                            Text(formatCost(model.costUSD))
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(.primary)
                                .frame(width: 48, alignment: .trailing)
                        }
                    }
                }
            } else if usage == nil {
                Text(store.isRefreshing ? "Loading…" : "No usage data")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            }
        }
        .padding(DesignSystem.cardPadding)
    }

    private func costColumn(label: String, amount: String, tokens: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.35))
            Text(amount)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(.primary)
            if let tok = tokens {
                Text(tok)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
    }
}

// MARK: - Full (alias to standard for now)

struct AIUsageFullView: View {
    var body: some View {
        AIUsageStandardView()
    }
}

// MARK: - Mini Bar Chart (14 vertical bars, no Charts dependency)

private struct MiniBarChart: View {
    let data: [DailyUsage]

    var body: some View {
        let maxVal = data.map(\.costUSD).max() ?? 1
        let today = Calendar.current.startOfDay(for: Date())

        HStack(alignment: .bottom, spacing: 3) {
            ForEach(data) { day in
                let frac = maxVal > 0 ? CGFloat(day.costUSD / maxVal) : 0
                let isToday = Calendar.current.startOfDay(for: day.date) == today
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(DesignSystem.claudeAmber.opacity(isToday ? 1.0 : 0.45 + 0.4 * frac))
                    .frame(maxWidth: .infinity)
                    .frame(height: max(2, 40 * frac))
            }
        }
        .frame(height: 40)
    }
}

// MARK: - Helpers

private func formatCost(_ usd: Double) -> String {
    if usd == 0 { return "$0.00" }
    if usd < 0.01 { return "<$0.01" }
    return String(format: "$%.2f", usd)
}

private func formatTokens(_ count: Int) -> String {
    if count >= 1_000_000 { return String(format: "%.1fM tok", Double(count) / 1_000_000) }
    if count >= 1_000 { return String(format: "%.0fK tok", Double(count) / 1_000) }
    return "\(count) tok"
}
