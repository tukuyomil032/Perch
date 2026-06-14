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

// MARK: - Mini (one-liner: icon + "Title · Artist")

struct NowPlayingMiniWidget: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let state = appState.nowPlayingManager.currentState
        HStack(spacing: 6) {
            if let artwork = state?.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 18, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: 18, height: 18)
            }
            if let s = state {
                Text(s.artist.isEmpty ? s.title : "\(s.title) · \(s.artist)")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.35))
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
