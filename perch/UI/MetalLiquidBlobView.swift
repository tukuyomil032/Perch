import SwiftUI

struct MetalLiquidBlobView: View {
    var separation: CGFloat
    var pillHeight: CGFloat = 34
    var providerLogoContent: AnyView

    private var circleR: CGFloat { pillHeight / 2 }
    private var maxOffset: CGFloat { circleR * 2 + 8 }

    var body: some View {
        let circleX = circleR + separation * maxOffset
        let totalWidth = circleR + separation * maxOffset + circleR

        ZStack(alignment: .trailing) {
            Rectangle()
                .fill(Color.black)
                .colorEffect(
                    ShaderLibrary.metaballMask(
                        .float2(0, pillHeight / 2),
                        .float2(circleX, pillHeight / 2),
                        .float(circleR)
                    )
                )
                .frame(width: totalWidth, height: pillHeight)

            providerLogoContent
                .frame(width: 16, height: 16)
                .padding(.trailing, 9)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.65), value: separation)
    }
}
