import SwiftUI

/// Rich mode's Home-module layout: a now-playing activity card on the left, a calendar
/// panel on the right.
///
/// Not preset-driven like Minimal mode's `presetContent` — this is a fixed layout, so
/// there's nothing here for `PresetTabBar` to switch between (see `ExpandedIslandView`).
struct AtollStyleExpandedView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            mainActivity
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider().opacity(0.08)
            CalendarWidget()
                .frame(width: 200, alignment: .leading)
        }
    }

    /// Now-playing when there's music; AI usage otherwise, so the main slot is never
    /// just blank while the calendar sidebar still has something to show.
    @ViewBuilder
    private var mainActivity: some View {
        if let state = appState.nowPlayingManager.currentState {
            NowPlayingCard(state: state, manager: appState.nowPlayingManager)
        } else {
            AIUsageStandardView()
        }
    }
}
