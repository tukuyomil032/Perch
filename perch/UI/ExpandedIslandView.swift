import SwiftUI

/// The island's expanded content: header, then the active preset's widgets.
///
/// Draws no background, no shape, no stroke and sets no width. All four used to live here
/// because the content sat inside a fixed-size window Perch positioned itself; the
/// vendored surface owns the chrome now and sizes itself to whatever this view reports, so
/// re-drawing a card in here would put a rounded rectangle inside the notch shape and
/// pin the surface to a width its own geometry did not choose.
struct ExpandedIslandView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.15)
            presetContent
                .animation(DesignSystem.springAnimation, value: appState.presetStore.activePresetID)
        }
        // Content-driven, but not unbounded: the widgets are laid out for roughly this
        // width, and without a floor the surface would shrink to the notch minimum on an
        // empty preset.
        .frame(minWidth: 420)
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
