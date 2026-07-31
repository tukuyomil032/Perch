import SwiftUI

/// The expanded island's top row: three zones per
/// docs/macOS-Expanded-Surface-Layout-Handbook-ja.md §8 ("ヘッダーの3領域設計") — left
/// (module switcher, `maxWidth: .infinity` leading), center (a reserved gap the width of
/// the physical/synthetic notch, so nothing renders under it), right (`SystemStatusCluster`,
/// `maxWidth: .infinity` trailing).
///
/// Modules reuse the existing `IslandCard` enum rather than a new type — `activeCard`
/// was kept through Phase A specifically for this (see `AppState.activeCard`'s doc
/// comment). Only `.nowPlaying` (Home) and `.aiUsage` have real content today, so those
/// are the only two buttons; `.fileShelf` / `.devStatus` / `.hud` stay unreachable until
/// their features exist.
struct IslandTopBar: View {
    private static let modules: [IslandCard] = [.nowPlaying, .aiUsage]

    /// The vendored surface has no environment-exposed path to `Nook.notchSize` (only
    /// `NookView` itself observes it), so this reads the same `NSScreen` extension the
    /// surface uses internally rather than threading a new value through Vendor. Falls
    /// back to `Nook.syntheticNotchWidth`'s own default (195pt) on displays with no
    /// physical notch and no live screen reference.
    private var notchReservationWidth: CGFloat {
        min(NSScreen.main?.notchSize?.width ?? 195, 300)
    }

    var body: some View {
        HStack(spacing: 0) {
            // No explicit close button — moving the cursor off the expanded surface
            // already collapses it (see `NookBridge`'s hover-exit handling), so a
            // dedicated affordance here was redundant chrome.
            ModuleSwitcher(modules: Self.modules)
                .frame(maxWidth: .infinity, alignment: .leading)

            Color.clear
                .frame(width: notchReservationWidth)

            HStack(spacing: 4) {
                SystemStatusCluster()
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }
}

private struct ModuleSwitcher: View {
    @Environment(AppState.self) private var appState
    let modules: [IslandCard]
    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: 8) {
            ForEach(modules) { module in
                Button {
                    withAnimation(DesignSystem.springAnimation) {
                        appState.expand(to: module)
                    }
                } label: {
                    Image(systemName: module.moduleIcon)
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(
                    ModuleIconButtonStyle(
                        isSelected: appState.activeCard == module,
                        namespace: selectionNamespace
                    )
                )
            }
        }
    }
}

private struct ModuleIconButtonStyle: ButtonStyle {
    let isSelected: Bool
    let namespace: Namespace.ID

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isSelected ? .white : .white.opacity(0.35))
            .frame(height: 26)
            .padding(.horizontal, 6)
            .background {
                if isSelected {
                    Capsule()
                        .fill(.white.opacity(0.12))
                        .matchedGeometryEffect(id: "moduleSelection", in: namespace)
                }
            }
            .contentShape(Rectangle())
    }
}

extension IslandCard {
    /// SF Symbol shown in the module switcher. Only `.nowPlaying` / `.aiUsage` are
    /// ever displayed today (see `IslandTopBar.modules`), but every case gets an icon
    /// so the switch stays exhaustive as the remaining modules land.
    fileprivate var moduleIcon: String {
        switch self {
        case .idle: "circle"
        case .nowPlaying: "house.fill"
        case .aiUsage: "chart.bar.horizontal.page"
        case .fileShelf: "square.and.arrow.up.on.square"
        case .devStatus: "hammer"
        case .hud: "dial.medium"
        }
    }
}

// Timer module (Phase B7, still unscheduled per docs/progress.md) is reserved to use
// SF Symbol "timer" once it gets an `IslandCard` case of its own.
