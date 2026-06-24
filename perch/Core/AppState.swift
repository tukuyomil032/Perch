import Foundation
import Logging

@MainActor
@Observable
final class AppState {
    var presentation: IslandPresentation = .compact
    var activeCard: IslandCard = .idle
    var latestError: String?
    var isPhysicalNotch: Bool = false
    var compactWindowSize: CGSize = CGSize(width: 150, height: 34)

    let presetStore = PresetStore()
    let widgetRegistry = WidgetRegistry()

    var openSettingsAction: (() -> Void)?

    let nowPlayingManager = NowPlayingManager()
    let aiUsageStore = AIUsageStore()

    private let logger = Logger(label: "com.tukuyomi032.perch.AppState")
    private var transitionGeneration = 0

    var isExpanded: Bool {
        presentation.expandsSurface
    }

    var expandedWindowHeight: CGFloat {
        guard let preset = presetStore.activePreset else { return 300 }
        let sizeHeights: [WidgetSize: CGFloat] = [.mini: 36, .compact: 52, .standard: 264, .full: 360]
        let widgetTotal = preset.widgets.map { sizeHeights[$0.size] ?? 44 }.reduce(0, +)
        let hasSidebar = preset.widgets.contains { $0.position != .main }
        return 40 + widgetTotal + (hasSidebar ? 1 : 0)
    }

    var compactWindowWidth: CGFloat {
        let isMusicActive = nowPlayingManager.currentState != nil
        let isAIActive = aiUsageStore.activeUsage != nil
        return (isMusicActive && isAIActive) ? 190 : 170
    }

    var compactWindowHeight: CGFloat { 44 }

    func expand(to card: IslandCard) {
        transitionGeneration += 1  // cancels any pending collapse task
        activeCard = card
        presentation = .expanded(card)
        logger.debug("Expanding island to card: \(card)")
    }

    func collapse() {
        guard let card = presentation.card else { return }

        transitionGeneration += 1
        let generation = transitionGeneration
        presentation = .collapsing(card)
        logger.debug("Collapsing island from card: \(card)")

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))

            guard
                let self,
                self.transitionGeneration == generation,
                self.presentation == .collapsing(card)
            else { return }

            self.presentation = .compact
            self.activeCard = .idle
        }
    }
}
