import Defaults
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

// MARK: - Provider logo helpers

private func providerLogoAssetName(_ id: String) -> String {
    switch id {
    case "claude": return "claude-logo"
    case "codex": return "codex-logo"
    case "gemini": return "gemini-logo"
    case "cursor": return "cursor-logo"
    case "openrouter": return "openrouter-logo"
    case "opencode": return "opencode-logo"
    default: return "claude-logo"
    }
}

@ViewBuilder
private func providerLogoImage(
    _ id: String, size: CGFloat, activeColor: AnyShapeStyle = AnyShapeStyle(DesignSystem.claudeAmber)
) -> some View {
    if id == "codex" {
        Image(providerLogoAssetName(id))
            .resizable()
            .renderingMode(.original)
            .frame(width: size, height: size)
    } else {
        Image(providerLogoAssetName(id))
            .resizable()
            .renderingMode(.template)
            .foregroundStyle(activeColor)
            .frame(width: size, height: size)
    }
}

// MARK: - Mini (tiny indicator, used in dual-activity pill or side slots)

struct AIUsageMiniView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let store = appState.aiUsageStore
        let id = store.activeProviderId ?? "claude"
        HStack(spacing: 5) {
            providerLogoImage(id, size: 9)
            Text(store.activeUsage?.planName ?? id.capitalized)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            if let cost = store.activeUsage?.cost {
                HStack(spacing: 3) {
                    Text(formatCost(cost.todayUSD))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)
                    if store.lastRefreshError != nil {
                        staleDataIndicator(size: 8)
                    }
                }
            } else {
                Text(store.isRefreshing ? "···" : "—")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Compact (one-liner for Music preset bottom bar)

struct AIUsageCompactView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let store = appState.aiUsageStore
        let usage = store.activeUsage
        let id = store.activeProviderId ?? "claude"

        HStack(spacing: 6) {
            providerLogoImage(id, size: 10)
            Text(usage?.planName ?? id.capitalized)
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
                    if store.lastRefreshError != nil {
                        staleDataIndicator(size: 8)
                    }
                    Text("today")
                        .font(.system(size: 9))
                        .foregroundStyle(.quaternary)
                }
            } else if let err = store.errors[id] {
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

    private var brandColor: Color {
        guard let id = appState.aiUsageStore.activeProviderId,
            let provider = appState.aiUsageStore.configuredProviders.first(where: { $0.id == id })
        else { return DesignSystem.claudeAmber }
        return Color(hex: provider.brandColorHex) ?? DesignSystem.claudeAmber
    }

    var body: some View {
        let store = appState.aiUsageStore
        let usage = store.activeUsage
        let chartData = Array((usage?.chartData ?? []).suffix(30))

        ZStack(alignment: .topLeading) {
            BackgroundVisualizerView(isPlaying: true, color: brandColor)
            VStack(alignment: .leading, spacing: 0) {
                // Provider header
                HStack {
                    Text(usage?.planName ?? (store.activeProviderId ?? "Claude").capitalized)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if store.configuredProviders.count > 1 {
                        Menu {
                            ForEach(store.configuredProviders, id: \.id) { provider in
                                Button {
                                    store.selectProvider(provider.id)
                                } label: {
                                    Label(
                                        provider.displayName,
                                        systemImage: store.activeProviderId == provider.id
                                            ? "checkmark" : ""
                                    )
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
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

                // Warning banner (OAuth failure or local log error)
                if let warning = usage?.warningMessage {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                        Text(warning)
                            .font(.system(size: 9))
                            .foregroundStyle(.orange.opacity(0.8))
                            .lineLimit(2)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                    .padding(.top, 6)
                }

                // Usage limits (session / weekly / daily) if available
                if usage?.session != nil || usage?.weekly != nil || usage?.daily != nil {
                    Spacer(minLength: 8)
                    UsageLimitsSection(
                        session: usage?.session,
                        weekly: usage?.weekly,
                        daily: usage?.daily,
                        accentColor: brandColor
                    )
                }

                Spacer(minLength: 10)

                // Cost 2-column
                HStack(alignment: .top, spacing: 0) {
                    costColumn(
                        label: "Today",
                        amount: usage?.cost.map { formatCost($0.todayUSD) } ?? "—",
                        tokens: usage?.cost.map { formatTokens($0.todayTokens) },
                        isStale: usage?.warningMessage != nil && usage?.cost != nil
                    )
                    Spacer()
                    costColumn(
                        label: "30 days",
                        amount: usage?.cost.map { formatCost($0.thirtyDayUSD) } ?? "—",
                        tokens: usage?.cost.map { formatTokens($0.thirtyDayTokens) },
                        isStale: usage?.warningMessage != nil && usage?.cost != nil
                    )
                }

                Spacer(minLength: 10)

                // Bar chart (30 days)
                if !chartData.isEmpty {
                    MiniBarChart(data: chartData, brandColor: brandColor)
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
                } else if usage == nil && store.isRefreshing {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 12)
                }
            }
            .padding(DesignSystem.cardPadding)
        }
    }

    private func costColumn(label: String, amount: String, tokens: String?, isStale: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.35))
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(amount)
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(.primary)
                if isStale {
                    staleDataIndicator(size: 9)
                }
            }
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

// MARK: - Usage Limits Section (session / weekly / daily progress bars)

private struct UsageLimitsSection: View {
    let session: UsageTier?
    let weekly: UsageTier?
    let daily: UsageTier?
    var accentColor: Color = DesignSystem.claudeAmber

    @Default(.aiUsageShowRemaining) private var showRemaining
    @Default(.aiUsageAbsoluteResetTime) private var absoluteResetTime
    @Default(.aiUsageShowPace) private var showPace
    @Default(.aiUsagePaceAbsoluteTime) private var paceAbsoluteTime

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let session {
                tierRow(tier: session)
            }
            if let weekly {
                tierRow(tier: weekly)
            }
            if let daily {
                tierRow(tier: daily)
            }
        }
        .padding(8)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func tierRow(tier: UsageTier) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            // ラベル
            Text(tier.label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))

            // プログレスバー
            GeometryReader { geo in
                let barFraction = showRemaining ? tier.remainingFraction : tier.usedFraction
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.12))
                        .frame(height: 5)
                    if barFraction > 0 {
                        Capsule()
                            .fill(progressColor(used: tier.usedFraction, showRemaining: showRemaining))
                            .frame(
                                width: geo.size.width * CGFloat(min(1, max(0, barFraction))),
                                height: 5
                            )
                    }
                }
            }
            .frame(height: 5)

            // 使用量/残り% + リセット時刻
            HStack {
                HStack(spacing: 4) {
                    Text(
                        showRemaining
                            ? "\(tier.remainingPercent)% 残り"
                            : "\(tier.usedPercent)% 使用"
                    )
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.55))
                    if tier.source == .localEstimate {
                        Text("(推定)")
                            .font(.system(size: 8))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }
                if let resetAt = tier.resetsAt {
                    Spacer()
                    Text(resetText(resetAt, absolute: absoluteResetTime))
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }

            // ペース行（余裕 / 枯渇予測）
            if showPace, let pace = tier.paceInfo() {
                HStack {
                    if pace.willSurvive {
                        Text("\(pace.surplusPercent)% 余裕")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color.green.opacity(0.85))
                    } else if let exhaustDate = pace.exhaustionDate {
                        Text(exhaustionText(exhaustDate, absolute: paceAbsoluteTime))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color.orange.opacity(0.9))
                    }
                    Spacer()
                    if pace.willSurvive {
                        Text("リセットまで持続")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.green.opacity(0.65))
                    }
                }
            }
        }
    }

    private func progressColor(used: Double, showRemaining: Bool) -> Color {
        if showRemaining {
            let remaining = 1.0 - used
            if remaining < 0.1 { return .red }
            if remaining < 0.3 { return .orange }
            return accentColor
        } else {
            if used > 0.9 { return .red }
            if used > 0.7 { return .orange }
            return accentColor
        }
    }

    private func resetText(_ date: Date, absolute: Bool) -> String {
        guard date > Date() else { return "リセット間近" }
        if absolute {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "ja_JP")
            formatter.dateFormat = Calendar.current.isDateInToday(date) ? "H:mm" : "M月d日 H:mm"
            return "\(formatter.string(from: date)) にリセット"
        } else {
            let fmt = RelativeDateTimeFormatter()
            fmt.unitsStyle = .abbreviated
            fmt.locale = Locale(identifier: "ja_JP")
            return "リセット \(fmt.localizedString(for: date, relativeTo: Date()))"
        }
    }

    private func exhaustionText(_ date: Date, absolute: Bool) -> String {
        if absolute {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "ja_JP")
            formatter.dateFormat = Calendar.current.isDateInToday(date) ? "H:mm" : "M月d日 H:mm"
            return "\(formatter.string(from: date)) に枯渇"
        } else {
            let secs = date.timeIntervalSinceNow
            if secs < 3600 {
                return "あと \(Int(secs / 60))分で枯渇"
            } else {
                return "あと \(String(format: "%.1f", secs / 3600))h で枯渇"
            }
        }
    }
}

// MARK: - Mini Bar Chart (30 vertical bars, no Charts dependency)

private struct MiniBarChart: View {
    let data: [DailyUsage]
    var brandColor: Color = DesignSystem.claudeAmber

    var body: some View {
        let maxVal = data.map(\.costUSD).max() ?? 1
        let today = Calendar.current.startOfDay(for: Date())

        HStack(alignment: .bottom, spacing: 2) {
            ForEach(data) { day in
                // Power curve 0.7 prevents extreme values from crushing the rest
                let frac = maxVal > 0 ? CGFloat(pow(day.costUSD / maxVal, 0.7)) : 0
                let isToday = Calendar.current.startOfDay(for: day.date) == today
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(brandColor.opacity(isToday ? 1.0 : 0.45 + 0.4 * frac))
                    .frame(maxWidth: .infinity)
                    .frame(height: max(2, 40 * frac))
            }
        }
        .frame(height: 40)
    }
}

// MARK: - Helpers

private func staleDataIndicator(size: CGFloat) -> some View {
    Image(systemName: "exclamationmark.triangle")
        .font(.system(size: size, weight: .medium))
        .foregroundStyle(.secondary)
        .help("Stale usage data")
}

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

private func formatResetDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d HH:mm"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    return formatter.string(from: date)
}
