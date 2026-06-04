import Defaults
import SwiftUI

struct RootIslandView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings
    @Namespace private var animation
    @Default(.animationSpeed) private var animationSpeed

    private var shapeAnimation: Animation {
        .spring(response: 0.30 / animationSpeed, dampingFraction: 0.88)
    }

    private var contentAnimation: Animation {
        .spring(response: 0.30 / animationSpeed, dampingFraction: 0.88)
            .delay(appState.isExpanded ? 0.05 : 0.0)
    }

    var body: some View {
        ZStack {
            if appState.isExpanded {
                ExpandedIslandView()
                    .matchedGeometryEffect(id: "island", in: animation)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.96).combined(with: .opacity),
                            removal: .scale(scale: 0.96).combined(with: .opacity)
                        )
                    )
                    .animation(contentAnimation, value: appState.isExpanded)
            } else {
                CompactPillView()
                    .matchedGeometryEffect(id: "island", in: animation)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.96).combined(with: .opacity),
                            removal: .scale(scale: 0.96).combined(with: .opacity)
                        )
                    )
                    .animation(contentAnimation, value: appState.isExpanded)
            }
        }
        .animation(shapeAnimation, value: appState.isExpanded)
        .onAppear { appState.openSettingsAction = { openSettings() } }
    }
}
