import SwiftUI

struct ExpandedIslandView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius, style: .continuous)
            .frame(width: 420, height: 180)
    }
}
