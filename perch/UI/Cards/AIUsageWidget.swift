import Charts
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

// MARK: - Mini (used in compact pill default state)

struct AIUsageMiniView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let store = appState.aiUsageStore
        HStack(spacing: 4) {
            Circle()
                .fill(claudeOrange)
                .frame(width: 6, height: 6)
            if let cost = store.activeUsage?.cost {
                Text(formatCost(cost.todayUSD))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)
            } else if store.isRefreshing {
                Text("···")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            } else {
                Text("No data")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Compact

struct AIUsageCompactView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let store = appState.aiUsageStore
        let usage = store.activeUsage

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Circle().fill(claudeOrange).frame(width: 5, height: 5)
                Text("Claude").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                if store.isRefreshing { ProgressView().scaleEffect(0.45) }
            }

            if let cost = usage?.cost {
                Text(formatCost(cost.todayUSD))
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(.primary)
                Text("today  /  " + formatCost(cost.thirtyDayUSD) + " 30d")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            } else if let err = store.errors["claude"] {
                Label(err, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                Text(store.isRefreshing ? "Loading…" : "—")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
    }
}

// MARK: - Standard

struct AIUsageStandardView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let store = appState.aiUsageStore
        let usage = store.activeUsage

        VStack(alignment: .leading, spacing: 0) {
            costHeader(usage: usage, isRefreshing: store.isRefreshing)
            Divider().opacity(0.25).padding(.vertical, 10)
            modelList(models: usage?.modelBreakdown ?? [], maxCost: usage?.cost?.todayUSD ?? 0)
        }
        .padding(DesignSystem.cardPadding)
    }

    private func costHeader(usage: AIUsageData?, isRefreshing: Bool) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Circle().fill(claudeOrange).frame(width: 6, height: 6)
                    Text("Claude Code").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    if isRefreshing { ProgressView().scaleEffect(0.45) }
                }
                Text(usage?.cost.map { formatCost($0.todayUSD) } ?? "—")
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundStyle(.primary)
                Text("today")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(usage?.cost.map { formatCost($0.thirtyDayUSD) } ?? "—")
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text("30 days")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func modelList(models: [ModelUsage], maxCost: Double) -> some View {
        let topModels = Array(models.prefix(3))
        return VStack(spacing: 6) {
            ForEach(topModels) { model in
                HStack(spacing: 8) {
                    Text(model.modelName)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Text(formatCost(model.costUSD))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.primary)
                }
            }
            if topModels.isEmpty {
                Text("No usage data")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
}

// MARK: - Full

struct AIUsageFullView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let store = appState.aiUsageStore
        let usage = store.activeUsage
        let chartData = Array((usage?.chartData ?? []).suffix(14))

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 4) {
                    Circle().fill(claudeOrange).frame(width: 6, height: 6)
                    Text("Claude Code").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                }
                Spacer()
                if store.isRefreshing {
                    ProgressView().scaleEffect(0.5)
                } else {
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if chartData.isEmpty {
                Text("No chart data available")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(height: 70)
            } else {
                Chart(chartData) { day in
                    BarMark(
                        x: .value("Date", day.date, unit: .day),
                        y: .value("Cost", day.costUSD)
                    )
                    .foregroundStyle(claudeOrange)
                    .cornerRadius(2)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2]))
                            .foregroundStyle(.tertiary)
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2]))
                            .foregroundStyle(.tertiary)
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(formatCostShort(v))
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                .frame(height: 70)
            }

            Divider().opacity(0.25)

            VStack(spacing: 6) {
                ForEach(usage?.modelBreakdown ?? []) { model in
                    HStack(spacing: 8) {
                        Text(model.modelName)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Text(formatTokens(model.totalTokens))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        Text(formatCost(model.costUSD))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.primary)
                            .frame(width: 52, alignment: .trailing)
                    }
                }
            }

            if let updated = usage?.lastUpdated {
                Text("Updated " + updated.formatted(.relative(presentation: .named)))
                    .font(.system(size: 9))
                    .foregroundStyle(.quaternary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(DesignSystem.cardPadding)
    }
}

// MARK: - Helpers

private let claudeOrange = Color(red: 0.91, green: 0.47, blue: 0.31)

private func formatCost(_ usd: Double) -> String {
    if usd == 0 { return "$0.00" }
    if usd < 0.01 { return "<$0.01" }
    return String(format: "$%.2f", usd)
}

private func formatCostShort(_ usd: Double) -> String {
    if usd == 0 { return "$0" }
    if usd < 1 { return String(format: "¢%.0f", usd * 100) }
    return String(format: "$%.1f", usd)
}

private func formatTokens(_ count: Int) -> String {
    if count >= 1_000_000 { return String(format: "%.1fM tok", Double(count) / 1_000_000) }
    if count >= 1_000 { return String(format: "%.0fK tok", Double(count) / 1_000) }
    return "\(count) tok"
}
