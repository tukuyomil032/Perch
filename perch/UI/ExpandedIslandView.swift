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
                header
                Divider().opacity(0.15)
                presetContent
                    .animation(DesignSystem.springAnimation, value: appState.presetStore.activePresetID)
            }
        }
        .frame(width: 420)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button {
                appState.collapse()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
                    .imageScale(.medium)
            }
            .buttonStyle(.plain)
            Spacer()
            PresetTabBar()
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    // MARK: - Preset Content (dynamic from WidgetRegistry)

    @ViewBuilder
    private var presetContent: some View {
        let placements = appState.presetStore.activePreset?.widgets ?? []
        let mainWidgets = placements.filter { $0.position == .main }
        let secondaryWidgets = placements.filter { $0.position != .main }

        VStack(spacing: 0) {
            ForEach(mainWidgets) { placement in
                widgetView(for: placement)
            }
            if !secondaryWidgets.isEmpty {
                Divider().opacity(0.08).padding(.horizontal, 12)
                ForEach(secondaryWidgets) { placement in
                    widgetView(for: placement)
                }
            }
        }
    }

    @ViewBuilder
    private func widgetView(for placement: WidgetPlacement) -> some View {
        if let widget = appState.widgetRegistry.widget(forId: placement.widgetId) {
            widget.body(size: placement.size)
        }
    }
}
