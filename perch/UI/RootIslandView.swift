import Defaults
import SwiftUI

struct RootIslandView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings
    @Default(.pillSize) private var pillSize

    private var compactSize: CGSize {
        appState.isPhysicalNotch
            ? appState.compactWindowSize
            : CGSize(width: pillSize.pillWidth, height: pillSize.pillHeight)
    }

    private var expandedSize: CGSize {
        CGSize(
            width: appState.isPhysicalNotch ? 460 : 420,
            height: appState.expandedWindowHeight
        )
    }

    private var currentTapShape: AnyShape {
        if appState.isExpanded {
            if appState.isPhysicalNotch {
                return AnyShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: DesignSystem.cardCornerRadius,
                        bottomTrailingRadius: DesignSystem.cardCornerRadius,
                        topTrailingRadius: 0,
                        style: .continuous
                    )
                )
            }
            return AnyShape(
                RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius, style: .continuous)
            )
        }
        return AnyShape(Capsule())
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
                        if appState.isExpanded {
                            ExpandedIslandView()
                                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        } else {
                            NowPlayingCompactContent(
                                state: state,
                                manager: appState.nowPlayingManager
                            )
                        }
                    }
                )
                .contentShape(currentTapShape)
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
