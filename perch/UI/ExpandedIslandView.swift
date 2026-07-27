import SwiftUI

struct ExpandedIslandView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            if #available(macOS 26, *) {
                RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius, style: .continuous)
                    .fill(.clear)
                    .glassEffect(
                        .regular.tint(.black.opacity(0.7)), in: .rect(cornerRadius: DesignSystem.cardCornerRadius))
            } else {
                Color.black
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius, style: .continuous))
                VibrancyBackground()
                    .opacity(0.35)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius, style: .continuous))
            }
            VStack(spacing: 0) {
                header
                Divider().opacity(0.15)
                presetContent
                    .animation(DesignSystem.springAnimation, value: appState.presetStore.activePresetID)
            }
        }
        .clipShape(cardShape)
        .overlay { cardStroke }
        .frame(width: appState.isPhysicalNotch ? 460 : 420)
    }

    private var cardShape: AnyShape {
        if appState.isPhysicalNotch {
            return AnyShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: DesignSystem.cardCornerRadius,
                    bottomTrailingRadius: DesignSystem.cardCornerRadius,
                    topTrailingRadius: 0,
                    style: .continuous
                )
            )
        }
        return AnyShape(
            RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius, style: .continuous)
        )
    }

    @ViewBuilder
    private var cardStroke: some View {
        if appState.isPhysicalNotch {
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: DesignSystem.cardCornerRadius,
                bottomTrailingRadius: DesignSystem.cardCornerRadius,
                topTrailingRadius: 0,
                style: .continuous
            )
            .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
        } else {
            RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
        }
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
                .frame(height: WidgetSizeMetrics.height(for: placement.size))
                .clipped()
        }
    }
}
