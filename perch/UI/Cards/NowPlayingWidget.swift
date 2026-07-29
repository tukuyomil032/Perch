import SwiftUI

// MARK: - PerchWidget Conformance

nonisolated struct NowPlayingWidget: PerchWidget {
    nonisolated let id = "now-playing"
    nonisolated let displayName = "Now Playing"
    nonisolated let icon = "music.note"
    nonisolated let supportedSizes: Set<WidgetSize> = [.mini, .compact, .standard]

    @MainActor func body(size: WidgetSize) -> AnyView {
        switch size {
        case .mini, .compact: AnyView(NowPlayingMiniWidget())
        case .standard, .full: AnyView(NowPlayingStandardWidget())
        }
    }
}

// MARK: - Mini (compact-pill slot: artwork thumbnail + marquee title/artist)

/// The compact leading slot's now-playing content.
///
/// This is what `IslandCompactLeading` used to draw inline before Phase B made the
/// slot registry-driven (see `IslandCompactSlots.swift`) — moved here verbatim so
/// selecting "now-playing" as `pillPrimary` reproduces the exact previous look.
struct NowPlayingMiniWidget: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if let state = appState.nowPlayingManager.currentState {
            HStack(spacing: 6) {
                NowPlayingArtworkThumbnail(state: state)
                MarqueeText(text: compactLabel(for: state), font: .system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: 120, maxHeight: 16)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
        } else {
            Color.clear.frame(width: 0, height: 0)
        }
    }

    private func compactLabel(for state: NowPlayingState) -> String {
        if state.isAd { return "Spotify Ad" }
        return state.artist.isEmpty ? state.title : "\(state.title) — \(state.artist)"
    }
}

// MARK: - Standard (existing NowPlayingCard)

struct NowPlayingStandardWidget: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if let state = appState.nowPlayingManager.currentState {
            NowPlayingCard(state: state, manager: appState.nowPlayingManager)
        } else {
            EmptyView()
        }
    }
}
