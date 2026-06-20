import SwiftUI

struct NowPlayingAmbientBackdrop: View {
    let artwork: NSImage?
    let isExpanded: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(isExpanded ? 0.10 : 0.20)

            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .scaleEffect(isExpanded ? 1.45 : 2.40)
                    .blur(radius: isExpanded ? 42 : 28)
                    .saturation(1.35)
                    .opacity(isExpanded ? 0.34 : 0.18)
            }
        }
        .animation(
            isExpanded ? DesignSystem.Motion.shellOpen : DesignSystem.Motion.shellClose,
            value: isExpanded
        )
    }
}
