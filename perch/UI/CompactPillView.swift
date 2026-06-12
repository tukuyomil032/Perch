import SwiftUI

struct CompactPillView: View {
    @Environment(AppState.self) private var appState
    @State private var isHovered = false
    @State private var isBouncing = false

    private var isMusicActive: Bool { appState.nowPlayingManager.currentState != nil }
    private var isAIActive: Bool { appState.aiUsageStore.activeUsage != nil }
    private var isDualActivity: Bool { isMusicActive && isAIActive }

    var body: some View {
        Group {
            if isDualActivity {
                dualActivityView
            } else {
                singlePillView
            }
        }
        .scaleEffect(isBouncing ? 1.05 : (isHovered ? 1.03 : 1.0))
        .animation(.spring(response: 0.2, dampingFraction: 0.5), value: isBouncing)
        .animation(DesignSystem.springAnimation, value: isHovered)
        .animation(DesignSystem.springAnimation, value: isDualActivity)
        .onHover { isHovered = $0 }
        .onChange(of: appState.nowPlayingManager.currentState?.title) { _, newTitle in
            guard newTitle != nil else { return }
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) { isBouncing = true }
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8).delay(0.15)) { isBouncing = false }
        }
        .onTapGesture { handleTap() }
    }

    // MARK: - Single pill (music OR AI OR default)

    private var singlePillView: some View {
        ZStack {
            VibrancyBackground()
            pillContent
        }
        .clipShape(Capsule())
        .frame(width: 150, height: 34)
    }

    @ViewBuilder
    private var pillContent: some View {
        Group {
            if let state = appState.nowPlayingManager.currentState {
                NowPlayingCompact(state: state)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else if isAIActive {
                aiCompactInline
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else {
                defaultContent
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(DesignSystem.springAnimation, value: isMusicActive)
        .animation(DesignSystem.springAnimation, value: isAIActive)
    }

    // MARK: - Dual activity: music capsule + AI circle

    private var dualActivityView: some View {
        HStack(spacing: 8) {
            // Left: music capsule
            ZStack {
                VibrancyBackground()
                if let state = appState.nowPlayingManager.currentState {
                    NowPlayingCompact(state: state)
                }
            }
            .clipShape(Capsule())
            .frame(width: 116, height: 34)

            // Right: AI usage circle (34pt)
            ZStack {
                Circle()
                    .fill(Color.black)
                    .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DesignSystem.claudeAmber)
            }
            .frame(width: 34, height: 34)
        }
    }

    // MARK: - AI inline (when music not playing but AI active)

    private var aiCompactInline: some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2)
                .fill(DesignSystem.claudeAmber)
                .frame(width: 7, height: 7)
            if let cost = appState.aiUsageStore.activeUsage?.cost {
                Text(formatCost(cost.todayUSD))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Default idle content

    private var defaultContent: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(.green)
                .frame(width: 6, height: 6)
            Text("Perch")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Tap handler

    private func handleTap() {
        if isMusicActive {
            appState.activePreset = .music
        } else if isAIActive {
            appState.activePreset = .ai
        }
        appState.expand(to: isMusicActive ? .nowPlaying : isAIActive ? .aiUsage : .idle)
    }
}

// MARK: - Helpers

private func formatCost(_ usd: Double) -> String {
    if usd == 0 { return "$0.00" }
    if usd < 0.01 { return "<$0.01" }
    return String(format: "$%.2f", usd)
}
