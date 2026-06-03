import SwiftUI

struct CompactPillView: View {
    @Environment(AppState.self) private var appState
    @State private var isHovered = false
    @State private var isBouncing = false

    var body: some View {
        ZStack {
            VibrancyBackground()
            pillContent
        }
        .clipShape(Capsule())
        .frame(width: 150, height: 34)
        .scaleEffect(isBouncing ? 1.05 : (isHovered ? 1.03 : 1.0))
        .animation(.spring(response: 0.2, dampingFraction: 0.5), value: isBouncing)
        .animation(DesignSystem.springAnimation, value: isHovered)
        .onHover { isHovered = $0 }
        .onChange(of: appState.nowPlayingManager.currentState?.title) { _, newTitle in
            guard newTitle != nil else { return }
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                isBouncing = true
            }
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8).delay(0.15)) {
                isBouncing = false
            }
        }
        .onTapGesture {
            let card: IslandCard = appState.nowPlayingManager.currentState != nil ? .nowPlaying : .idle
            appState.expand(to: card)
        }
    }

    @ViewBuilder
    private var pillContent: some View {
        Group {
            if let state = appState.nowPlayingManager.currentState {
                NowPlayingCompact(state: state)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else {
                defaultContent
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(DesignSystem.springAnimation, value: appState.nowPlayingManager.currentState != nil)
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
