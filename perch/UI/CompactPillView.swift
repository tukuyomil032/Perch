import SwiftUI

struct CompactPillView: View {
    @Environment(AppState.self) private var appState
    @State private var isHovered = false

    var body: some View {
        ZStack {
            VibrancyBackground()
            pillContent
        }
        .clipShape(Capsule())
        .frame(width: 150, height: 34)
        .scaleEffect(isHovered ? 1.03 : 1.0)
        .animation(DesignSystem.springAnimation, value: isHovered)
        .onHover { isHovered = $0 }
        .onTapGesture {
            let card: IslandCard = appState.nowPlayingManager.currentState != nil ? .nowPlaying : .idle
            appState.expand(to: card)
        }
    }

    @ViewBuilder
    private var pillContent: some View {
        if let state = appState.nowPlayingManager.currentState {
            NowPlayingCompact(state: state)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
        } else {
            defaultContent
        }
    }

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
}
