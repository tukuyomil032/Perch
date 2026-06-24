import SwiftUI

struct IslandGlassSurface<Backdrop: View, Content: View>: View {
    let isExpanded: Bool
    let isPhysicalNotch: Bool
    let compactSize: CGSize
    let expandedSize: CGSize

    @ViewBuilder private let backdrop: Backdrop
    @ViewBuilder private let content: Content

    init(
        isExpanded: Bool,
        isPhysicalNotch: Bool,
        compactSize: CGSize,
        expandedSize: CGSize,
        @ViewBuilder backdrop: () -> Backdrop,
        @ViewBuilder content: () -> Content
    ) {
        self.isExpanded = isExpanded
        self.isPhysicalNotch = isPhysicalNotch
        self.compactSize = compactSize
        self.expandedSize = expandedSize
        self.backdrop = backdrop()
        self.content = content()
    }

    private var size: CGSize {
        isExpanded ? expandedSize : compactSize
    }

    private var cornerRadius: CGFloat {
        isExpanded ? DesignSystem.cardCornerRadius : DesignSystem.pillCornerRadius
    }

    var body: some View {
        Group {
            if isPhysicalNotch {
                surface(
                    in: UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: cornerRadius,
                        bottomTrailingRadius: cornerRadius,
                        topTrailingRadius: 0,
                        style: .continuous
                    )
                )
            } else if isExpanded {
                surface(
                    in: RoundedRectangle(
                        cornerRadius: cornerRadius,
                        style: .continuous
                    )
                )
            } else {
                surface(in: Capsule())
            }
        }
        .frame(width: size.width, height: size.height)
        .animation(
            isExpanded ? DesignSystem.Motion.shellOpen : DesignSystem.Motion.shellClose,
            value: isExpanded
        )
    }

    @ViewBuilder
    private func surface<S: InsettableShape>(in shape: S) -> some View {
        ZStack {
            backdrop
                .clipShape(shape)

            if #available(macOS 26, *) {
                shape
                    .fill(.clear)
                    .glassEffect(.regular, in: shape)
            } else {
                VibrancyBackground()
                    .clipShape(shape)

                shape
                    .fill(.black.opacity(0.20))
            }

            content
        }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(
                .white.opacity(isExpanded ? 0.14 : 0.09),
                lineWidth: 0.5
            )
        }
        .shadow(
            color: .black.opacity(isExpanded ? 0.28 : 0.18),
            radius: isExpanded ? 20 : 10,
            y: isExpanded ? 10 : 5
        )
    }
}
