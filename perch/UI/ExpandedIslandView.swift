import SwiftUI

struct ExpandedIslandView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            VibrancyBackground()
                .clipShape(
                    RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius, style: .continuous)
                )

            VStack(spacing: 0) {
                header
                Divider().opacity(0.15)
                presetContent
                    .animation(DesignSystem.springAnimation, value: appState.activePreset)
            }
        }
        .frame(width: 420)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button {
                appState.collapse()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
                    .imageScale(.medium)
            }
            .buttonStyle(.plain)
            Spacer()
            PresetTabBar()
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    // MARK: - Preset Content

    @ViewBuilder
    private var presetContent: some View {
        switch appState.activePreset {
        case .daily:
            dailyLayout
        case .dev:
            devLayout
        }
    }

    // MARK: - Daily: NowPlaying (primary) + AI mini (secondary)

    private var dailyLayout: some View {
        VStack(spacing: 0) {
            NowPlayingStandardWidget()
            Divider()
                .opacity(0.08)
                .padding(.horizontal, 12)
            AIUsageCompactView()
        }
    }

    // MARK: - Dev: AI Usage (primary) + NowPlaying mini (secondary)

    private var devLayout: some View {
        VStack(spacing: 0) {
            AIUsageStandardView()
            Divider()
                .opacity(0.08)
                .padding(.horizontal, 12)
            NowPlayingMiniWidget()
        }
    }
}
