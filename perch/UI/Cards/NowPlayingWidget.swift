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

// MARK: - Mini (compact-pill slot: artwork thumbnail only)

/// The compact leading slot's now-playing content.
///
/// Artwork only, deliberately — the title/artist marquee this used to show alongside it
/// is gone. The compact pill is glanceable chrome, not a place to read text; the track
/// name belongs to the expanded view, one hover or click away.
struct NowPlayingMiniWidget: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if let state = appState.nowPlayingManager.currentState {
            NowPlayingArtworkThumbnail(state: state)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
        } else {
            Color.clear.frame(width: 0, height: 0)
        }
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
