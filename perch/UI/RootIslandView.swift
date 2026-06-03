import Defaults
import SwiftUI

struct RootIslandView: View {
    @Environment(AppState.self) private var appState
    @Namespace private var animation
    @Default(.animationSpeed) private var animationSpeed

    // iOS Dynamic Island: faster response, bouncier damping
    private var shapeAnimation: Animation {
        .spring(response: 0.28 / animationSpeed, dampingFraction: 0.65)
    }

    // Content appears slightly after shape on expand, simultaneous on collapse
    private var contentAnimation: Animation {
        .spring(response: 0.30 / animationSpeed, dampingFraction: 0.70)
            .delay(appState.isExpanded ? 0.06 : 0.0)
    }

    var body: some View {
        ZStack {
            if appState.isExpanded {
                ExpandedIslandView()
                    .matchedGeometryEffect(id: "island", in: animation)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.92).combined(with: .opacity),
                            removal: .scale(scale: 0.92).combined(with: .opacity)
                        )
                    )
                    .animation(contentAnimation, value: appState.isExpanded)
            } else {
                CompactPillView()
                    .matchedGeometryEffect(id: "island", in: animation)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.92).combined(with: .opacity),
                            removal: .scale(scale: 0.92).combined(with: .opacity)
                        )
                    )
                    .animation(contentAnimation, value: appState.isExpanded)
            }
        }
        .animation(shapeAnimation, value: appState.isExpanded)
    }
}
