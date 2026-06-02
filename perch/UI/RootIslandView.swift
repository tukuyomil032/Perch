import Defaults
import SwiftUI

struct RootIslandView: View {
    @Environment(AppState.self) private var appState
    @Namespace private var animation
    @Default(.animationSpeed) private var animationSpeed

    private var expandAnimation: Animation {
        .spring(response: 0.35 / animationSpeed, dampingFraction: 0.86)
    }

    var body: some View {
        ZStack {
            if appState.isExpanded {
                ExpandedIslandView()
                    .matchedGeometryEffect(id: "island", in: animation)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.8).combined(with: .opacity),
                            removal: .scale(scale: 0.8).combined(with: .opacity)
                        ))
            } else {
                CompactPillView()
                    .matchedGeometryEffect(id: "island", in: animation)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.8).combined(with: .opacity),
                            removal: .scale(scale: 0.8).combined(with: .opacity)
                        ))
            }
        }
        .animation(expandAnimation, value: appState.isExpanded)
    }
}
