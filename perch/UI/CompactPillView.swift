import SwiftUI

struct CompactPillView: View {
    @Environment(AppState.self) private var appState
    @State private var isHovered = false

    var body: some View {
        ZStack {
            VibrancyBackground()
                .clipShape(Capsule())

            Button(action: { appState.expand(to: .idle) }) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(.green)
                        .frame(width: 6, height: 6)
                    Text("Perch")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 16)
            }
            .buttonStyle(.plain)
        }
        .frame(width: 150, height: 34)
        .scaleEffect(isHovered ? 1.03 : 1.0)
        .animation(DesignSystem.springAnimation, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
