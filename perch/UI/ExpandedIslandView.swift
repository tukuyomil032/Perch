import SwiftUI

struct ExpandedIslandView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            VibrancyBackground()
                .clipShape(
                    RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius, style: .continuous)
                )

            VStack(spacing: 0) {
                HStack {
                    Text("Perch")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button { appState.collapse() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                            .imageScale(.medium)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

                Divider().opacity(0.3)

                VStack(spacing: 8) {
                    Image(systemName: "bird")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("Nothing here yet")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                }
                .frame(height: 100)
                .padding(16)
            }
        }
        .frame(width: 420)
    }
}
