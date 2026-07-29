import SwiftUI

/// The expanded island's top row: collapse button + module switcher on the left,
/// system status glyphs on the right.
///
/// Modules reuse the existing `IslandCard` enum rather than a new type — `activeCard`
/// was kept through Phase A specifically for this (see `AppState.activeCard`'s doc
/// comment). Only `.nowPlaying` (Home) and `.aiUsage` have real content today, so those
/// are the only two buttons; `.fileShelf` / `.devStatus` / `.hud` stay unreachable until
/// their features exist.
struct IslandTopBar: View {
    @Environment(AppState.self) private var appState

    private static let modules: [IslandCard] = [.nowPlaying, .aiUsage]

    var body: some View {
        HStack {
            Button {
                appState.collapse()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
                    .imageScale(.medium)
            }
            .buttonStyle(.plain)

            ModuleSwitcher(modules: Self.modules)

            Spacer()
            SystemStatusCluster()
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }
}

private struct ModuleSwitcher: View {
    @Environment(AppState.self) private var appState
    let modules: [IslandCard]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(modules) { module in
                Button {
                    withAnimation(DesignSystem.springAnimation) {
                        appState.expand(to: module)
                    }
                } label: {
                    Image(systemName: module.moduleIcon)
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(ModuleIconButtonStyle(isSelected: appState.activeCard == module))
            }
        }
        .padding(.leading, 10)
    }
}

private struct ModuleIconButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isSelected ? .white : .white.opacity(0.35))
            .frame(width: 24, height: 24)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.white.opacity(0.12))
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
        case .nowPlaying: "music.note"
        case .aiUsage: "sparkles"
        case .fileShelf: "tray"
        case .devStatus: "hammer"
        case .hud: "dial.medium"
        }
    }
}
