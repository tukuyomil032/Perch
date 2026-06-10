import SwiftUI

/// boring.notch スタイルの physicalNotch 専用展開ビュー。
/// 水平レイアウト: アルバムアート（左）+ 曲情報・シークバー・コントロール（右）。
/// 上角フラッシュ・下角丸めで画面最上端のノッチと一体化する。
struct NotchExpandedView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            VibrancyBackground()
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: DesignSystem.cardCornerRadius,
                        bottomTrailingRadius: DesignSystem.cardCornerRadius,
                        topTrailingRadius: 0,
                        style: .continuous
                    )
                )

            let manager = appState.nowPlayingManager
            if let state = manager.currentState {
                NotchNowPlayingContent(state: state, manager: manager)
            } else {
                emptyState
            }
        }
        .frame(width: 460, height: 220)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("Play some music")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Content

private struct NotchNowPlayingContent: View {
    let state: NowPlayingState
    let manager: NowPlayingManager

    @State private var displayedArtwork: NSImage?
    @State private var displayedArtworkID: UUID?
    @State private var artworkAngle: Double = 0
    @State private var isScrubbing = false
    @State private var scrubProgress: Double = 0

    var body: some View {
        HStack(spacing: 0) {
            artworkSection
            infoSection
        }
        .onAppear {
            displayedArtwork = state.artwork
            displayedArtworkID = state.artworkID
        }
        .onChange(of: state.artworkID) { _, newID in
            guard let newID, newID != displayedArtworkID else { return }
            Task { @MainActor in
                withAnimation(.easeIn(duration: 0.18)) { artworkAngle = 90 }
                try? await Task.sleep(for: .milliseconds(180))
                // Read from manager.currentState after sleep — captured `state` may be stale
                // (SwiftUI closures capture value types at closure-creation time)
                if manager.currentState?.artworkID == newID {
                    displayedArtwork = manager.currentState?.artwork
                    displayedArtworkID = newID
                }
                withAnimation(.easeOut(duration: 0.18)) { artworkAngle = 0 }
            }
        }
    }

    // MARK: Album Art

    private var artworkSection: some View {
        Group {
            if let img = displayedArtwork {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 220, height: 220)
                    .clipped()
            } else {
                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 220, height: 220)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 40, weight: .light))
                            .foregroundStyle(.white.opacity(0.3))
                    }
            }
        }
        .rotation3DEffect(.degrees(artworkAngle), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
    }

    // MARK: Info + Controls

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 曲名・アーティスト
            VStack(alignment: .leading, spacing: 3) {
                Text(state.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(state.artist)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            .padding(.top, 20)
            .padding(.horizontal, 16)

            Spacer()

            // シークバー
            seekBar
                .padding(.horizontal, 16)

            Spacer()

            // コントロール
            controls
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
        }
        .frame(width: 240)
    }

    // MARK: Seek Bar

    private var seekBar: some View {
        VStack(spacing: 3) {
            GeometryReader { geo in
                TimelineView(.animation(minimumInterval: 0.1, paused: !state.isPlaying || isScrubbing)) { ctx in
                    let p = isScrubbing ? scrubProgress : state.liveProgress(at: ctx.date)
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.15)).frame(height: isScrubbing ? 5 : 3)
                        Capsule()
                            .fill(.white.opacity(isScrubbing ? 1.0 : 0.8))
                            .frame(width: max(0, geo.size.width * p), height: isScrubbing ? 5 : 3)
                    }
                    .animation(.easeInOut(duration: 0.08), value: isScrubbing)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isScrubbing = true
                            scrubProgress = max(0, min(1, value.location.x / geo.size.width))
                        }
                        .onEnded { value in
                            let pos = max(0, min(1, value.location.x / geo.size.width))
                            if let dur = state.duration { manager.seek(to: pos * dur) }
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(300))
                                isScrubbing = false
                            }
                        }
                )
            }
            .frame(height: 14)

            TimelineView(.animation(minimumInterval: 1.0, paused: !state.isPlaying)) { ctx in
                HStack {
                    Text(isScrubbing ? scrubElapsed : state.liveFormattedElapsed(at: ctx.date))
                    Spacer()
                    Text(isScrubbing ? scrubRemaining : (state.liveRemaining(at: ctx.date) ?? state.formattedDuration))
                }
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 0) {
            Spacer()
            ctrlButton("backward.fill", size: 16, action: manager.previousTrack)
            Spacer()
            ctrlButton(state.isPlaying ? "pause.fill" : "play.fill", size: 20, action: manager.togglePlayPause)
            Spacer()
            ctrlButton("forward.fill", size: 16, action: manager.nextTrack)
            Spacer()
        }
    }

    private func ctrlButton(_ symbol: String, size: CGFloat, action: @escaping @MainActor () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Scrub Labels

    private var scrubElapsed: String {
        guard let dur = state.duration else { return "-:--" }
        let s = max(0, Int(scrubProgress * dur))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private var scrubRemaining: String {
        guard let dur = state.duration else { return "-:--" }
        let s = max(0, Int(dur - scrubProgress * dur))
        return String(format: "-%d:%02d", s / 60, s % 60)
    }
}
