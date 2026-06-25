import SwiftUI

struct PresetTabBar: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 4) {
            ForEach(appState.presetStore.presets) { preset in
                Button(preset.name) {
                    withAnimation(DesignSystem.springAnimation) {
                        appState.presetStore.select(id: preset.id)
                    }
                }
                .buttonStyle(PresetTabButtonStyle(isSelected: appState.presetStore.activePresetID == preset.id))
                .highPriorityGesture(
                    TapGesture().onEnded {
                        withAnimation(DesignSystem.springAnimation) {
                            appState.presetStore.select(id: preset.id)
                        }
                    }
                )
            }
        }
    }
}

// MARK: - Button Style

private struct PresetTabButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? .white : .white.opacity(0.35))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.white.opacity(0.12))
                }
            }
            .contentShape(Rectangle())
    }
}
