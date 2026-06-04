import Defaults
import SwiftUI

struct RootIslandView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings
    @Default(.animationSpeed) private var animationSpeed

    private var openAnimation: Animation {
        .spring(response: 0.42 / animationSpeed, dampingFraction: 0.80)
    }

    private var closeAnimation: Animation {
        .spring(response: 0.38 / animationSpeed, dampingFraction: 1.00)
    }

    private var contentAnimation: Animation {
        appState.isExpanded
            ? openAnimation.delay(0.05)
            : closeAnimation
    }

    var body: some View {
        ZStack {
            if appState.isExpanded {
                ExpandedIslandView()
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.94, anchor: .top).combined(with: .opacity),
                            removal: .scale(scale: 0.94, anchor: .top).combined(with: .opacity)
                        )
                    )
                    .animation(contentAnimation, value: appState.isExpanded)
            } else {
                CompactPillView()
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.94, anchor: .top).combined(with: .opacity),
                            removal: .scale(scale: 0.94, anchor: .top).combined(with: .opacity)
                        )
                    )
                    .animation(contentAnimation, value: appState.isExpanded)
            }
        }
        .animation(
            appState.isExpanded ? openAnimation : closeAnimation,
            value: appState.isExpanded
        )
        .onAppear {
            appState.openSettingsAction = { openSettings() }
        }
    }
}
