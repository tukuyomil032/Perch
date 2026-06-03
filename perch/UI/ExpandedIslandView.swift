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
                Divider().opacity(0.3)
                cardContent
            }
        }
        .frame(width: 420)
    }

    private var header: some View {
        HStack {
            Text("Perch")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                appState.collapse()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
                    .imageScale(.medium)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var cardContent: some View {
        let manager = appState.nowPlayingManager
        switch appState.activeCard {
        case .nowPlaying:
            if let state = manager.currentState {
                NowPlayingCard(state: state, manager: manager)
            } else {
                emptyState(icon: "music.note", message: "音楽を再生してください")
            }
        case .idle:
            emptyState(icon: "bird", message: "Nothing here yet")
        default:
            emptyState(icon: "questionmark", message: "Coming soon")
        }
    }

    private func emptyState(icon: String, message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
        }
        .frame(height: 100)
        .padding(16)
    }
}
