import Defaults
import SwiftUI

struct RootIslandView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings
    @Default(.pillSize) private var pillSize

    private var compactSize: CGSize {
        CGSize(width: pillSize.pillWidth, height: pillSize.pillHeight)
    }

    private var expandedSize: CGSize {
        CGSize(width: 420, height: appState.expandedWindowHeight)
    }

    var body: some View {
        Group {
            if let state = appState.nowPlayingManager.currentState {
                IslandGlassSurface(
                    isExpanded: appState.isExpanded,
                    isPhysicalNotch: appState.isPhysicalNotch,
                    compactSize: compactSize,
                    expandedSize: expandedSize,
                    backdrop: {
                        NowPlayingAmbientBackdrop(
                            artwork: state.artwork,
                            isExpanded: appState.isExpanded
                        )
                    },
                    content: {
                        NowPlayingMorphContent(
                            state: state,
                            manager: appState.nowPlayingManager,
                            isExpanded: appState.isExpanded,
                            showsDetails: appState.showsExpandedDetails
                        )
                    }
                )
                .contentShape(Capsule())
                .onTapGesture {
                    if appState.isExpanded {
                        appState.collapse()
                    } else {
                        appState.expand(to: .nowPlaying)
                    }
                }
            } else {
                CompactPillView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            appState.openSettingsAction = { openSettings() }
        }
    }
}
