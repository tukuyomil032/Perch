import SwiftUI

struct RootIslandView: View {
    @Environment(AppState.self) private var appState
    @Namespace private var animation

    var body: some View {
        ZStack {
            if appState.isExpanded {
                ExpandedIslandView()
                    .matchedGeometryEffect(id: "island", in: animation)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.8).combined(with: .opacity),
                        removal: .scale(scale: 0.8).combined(with: .opacity)
                    ))
            } else {
                CompactPillView()
                    .matchedGeometryEffect(id: "island", in: animation)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.8).combined(with: .opacity),
                        removal: .scale(scale: 0.8).combined(with: .opacity)
                    ))
            }
        }
        .animation(DesignSystem.expandAnimation, value: appState.isExpanded)
    }
}
