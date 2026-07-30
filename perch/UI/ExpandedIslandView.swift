import Defaults
import SwiftUI

/// The island's expanded content: header, then the active module's content.
///
/// Draws no background, no shape, no stroke and sets no width. All four used to live here
/// because the content sat inside a fixed-size window Perch positioned itself; the
/// vendored surface owns the chrome now and sizes itself to whatever this view reports, so
/// re-drawing a card in here would put a rounded rectangle inside the notch shape and
/// pin the surface to a width its own geometry did not choose.
struct ExpandedIslandView: View {
    @Environment(AppState.self) private var appState
    @Default(.uiMode) private var uiMode

    var body: some View {
        VStack(spacing: 0) {
            IslandTopBar()
            // Preset switching is a Minimal-mode-only concept — Rich mode's Home module is
            // a fixed layout (`AtollStyleExpandedView`), not preset-driven, so there is
            // nothing for a preset tab bar to switch between.
            if uiMode == .minimal, IslandModuleContent.showsPresetTabBar(for: appState.activeCard) {
                HStack {
                    Spacer()
                    PresetTabBar()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
            Divider().opacity(0.15)
            moduleContent
                .animation(DesignSystem.springAnimation, value: appState.presetStore.activePresetID)
                .animation(DesignSystem.springAnimation, value: appState.activeCard)
        }
        // Content-driven, but not unbounded: the widgets are laid out for roughly this
        // width, and without a floor the surface would shrink to the notch minimum on an
        // empty preset.
        .frame(minWidth: minExpandedWidth)
    }

    /// Rich mode's 3-column Home layout wants more room than Minimal mode's single-column
    /// widget stack or the AI Usage full-screen view, so only widen the floor when
    /// `AtollStyleExpandedView` is actually what's rendering.
    private var minExpandedWidth: CGFloat {
        guard uiMode == .rich, IslandModuleContent.content(for: appState.activeCard) == .presetDriven
        else { return 420 }
        return DesignSystem.richModeMinWidth
    }

    // MARK: - Module Content

    /// Routes to the active module's content. `.nowPlaying` (Home) renders
    /// `AtollStyleExpandedView` in Rich mode or the active preset's widgets in Minimal
    /// mode; `.aiUsage` bypasses both entirely and shows the full AI usage screen
    /// regardless of `uiMode` — it was never preset-driven to begin with. See
    /// `IslandModuleContent` for the pure mapping this switches on.
    @ViewBuilder
    private var moduleContent: some View {
        switch IslandModuleContent.content(for: appState.activeCard) {
        case .presetDriven:
            if uiMode == .rich {
                AtollStyleExpandedView()
            } else {
                presetContent
            }
        case .aiUsageDirect: AIUsageFullView()
        case .empty: EmptyView()
        }
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
