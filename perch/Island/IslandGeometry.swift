import AppKit

enum IslandGeometry {
    static func compactFrame(mode: IslandMode, environment: ScreenEnvironment, width: CGFloat? = nil) -> CGRect {
        centeredFrame(
            size: compactSize(mode: mode, width: width), topOffset: topOffset(mode: mode), environment: environment,
            mode: mode)
    }

    static func expandedFrame(mode: IslandMode, environment: ScreenEnvironment, height: CGFloat? = nil) -> CGRect {
        centeredFrame(
            size: expandedSize(mode: mode, height: height),
            topOffset: topOffset(mode: mode), environment: environment, mode: mode)
    }

    static func compactFrame(mode: IslandMode, screen: NSScreen) -> CGRect {
        compactFrame(mode: mode, environment: ScreenEnvironment.live(screen: screen), width: nil)
    }

    static func expandedFrame(mode: IslandMode, screen: NSScreen) -> CGRect {
        expandedFrame(mode: mode, environment: ScreenEnvironment.live(screen: screen))
    }

    private static func compactSize(mode: IslandMode, width: CGFloat? = nil) -> CGSize {
        switch mode {
        case .floatingPill:
            return CGSize(width: width ?? 150, height: 34)
        case .physicalNotch(let notchSize):
            return CGSize(width: max(notchSize.width, 150), height: max(notchSize.height, 32))
        }
    }

    private static func expandedSize(mode: IslandMode, height: CGFloat? = nil) -> CGSize {
        switch mode {
        case .floatingPill: return CGSize(width: 420, height: height ?? 280)
        case .physicalNotch: return CGSize(width: 460, height: 220)
        }
    }

    private static func topOffset(mode: IslandMode) -> CGFloat {
        switch mode {
        case .floatingPill: return 20
        case .physicalNotch: return 0
        }
    }

    private static func centeredFrame(
        size: CGSize, topOffset: CGFloat, environment: ScreenEnvironment, mode: IslandMode
    ) -> CGRect {
        // physicalNotch must be flush with the true screen top (above menu bar area).
        // visibleFrame.maxY is below the menu bar — using it would offset the notch window downward.
        let sf = mode == .floatingPill ? environment.visibleFrame : environment.frame
        return CGRect(
            x: sf.midX - size.width / 2,
            y: sf.maxY - size.height - topOffset,
            width: size.width,
            height: size.height
        )
    }
}
