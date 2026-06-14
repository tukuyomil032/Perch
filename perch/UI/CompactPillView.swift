import SwiftUI

struct CompactPillView: View {
    @Environment(AppState.self) private var appState
    @State private var isHovered = false
    @State private var isBouncing = false

    private var isMusicActive: Bool { appState.nowPlayingManager.currentState != nil }
    private var isAIActive: Bool { appState.aiUsageStore.activeUsage != nil }
    private var isDualActivity: Bool { isMusicActive && isAIActive }
    private var isIdle: Bool { !isMusicActive && !isAIActive }

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
        .opacity(isIdle && !isHovered ? 0.12 : 1.0)
        .animation(.easeInOut(duration: 0.25), value: isIdle)
        .animation(.easeInOut(duration: 0.25), value: isHovered)
        .onTapGesture { handleTap() }
    }

    // MARK: - Single pill (music OR AI OR default)

    private var singlePillView: some View {
        pillContent
            .frame(width: 150, height: 34)
            .background(Color.black, in: Capsule())
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
            }
        }
        .animation(DesignSystem.springAnimation, value: isMusicActive)
        .animation(DesignSystem.springAnimation, value: isAIActive)
    }

    // MARK: - Dual activity: music capsule + provider logo circle

    private var dualActivityView: some View {
        HStack(spacing: 8) {
            // Left: music capsule — using SwiftUI material to avoid NSVisualEffectView clip bleed
            if let state = appState.nowPlayingManager.currentState {
                NowPlayingCompact(state: state)
                    .frame(width: 116, height: 34)
                    .background(Color.black, in: Capsule())
            }

            // Right: most-used provider logo circle
            ZStack {
                Circle()
                    .fill(.black)
                    .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
                providerLogoView
                    .frame(width: 16, height: 16)
            }
            .frame(width: 34, height: 34)
            .clipShape(Circle())  // clip corners so no gray bleed from hosting view
        }
    }

    private var providerLogoView: some View {
        let id = appState.aiUsageStore.mostUsedProviderId ?? "claude"
        let assetName = providerLogoAssetName(id)
        if id == "codex" {
            return AnyView(
                Image(assetName)
                    .resizable()
                    .renderingMode(.original)
                    .frame(width: 16, height: 16)
            )
        }
        return AnyView(
            Image(assetName)
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(DesignSystem.claudeAmber)
                .frame(width: 16, height: 16)
        )
    }

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

    // MARK: - AI inline (when music not playing but AI active)

    private var aiCompactInline: some View {
        HStack(spacing: 5) {
            let id = appState.aiUsageStore.mostUsedProviderId ?? "claude"
            if id == "codex" {
                Image(providerLogoAssetName(id))
                    .resizable()
                    .renderingMode(.original)
                    .frame(width: 10, height: 10)
            } else {
                Image(providerLogoAssetName(id))
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(DesignSystem.claudeAmber)
                    .frame(width: 10, height: 10)
            }
            if let cost = appState.aiUsageStore.activeUsage?.cost {
                Text(formatCost(cost.todayUSD))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Tap handler

    private func handleTap() {
        guard !isIdle else { return }
        appState.expand(to: isMusicActive ? .nowPlaying : .aiUsage)
    }
}

// MARK: - Helpers

private func formatCost(_ usd: Double) -> String {
    if usd == 0 { return "$0.00" }
    if usd < 0.01 { return "<$0.01" }
    return String(format: "$%.2f", usd)
}
