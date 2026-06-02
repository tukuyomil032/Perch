import AppKit

enum IslandGeometry {
    static func compactFrame(mode: IslandMode, screen: NSScreen) -> CGRect {
        centeredFrame(size: compactSize(mode: mode), topOffset: topOffset(mode: mode), screen: screen)
    }

    static func expandedFrame(mode: IslandMode, screen: NSScreen) -> CGRect {
        centeredFrame(size: expandedSize(mode: mode), topOffset: topOffset(mode: mode), screen: screen)
    }

    private static func compactSize(mode: IslandMode) -> CGSize {
        switch mode {
        case .floatingPill:
            return CGSize(width: 150, height: 34)
        case .physicalNotch(let notchSize):
            return CGSize(width: max(notchSize.width, 150), height: max(notchSize.height, 32))
        }
    }

    private static func expandedSize(mode: IslandMode) -> CGSize {
        switch mode {
        case .floatingPill: return CGSize(width: 420, height: 180)
        case .physicalNotch: return CGSize(width: 460, height: 190)
        }
    }

    private static func topOffset(mode: IslandMode) -> CGFloat {
        switch mode {
        case .floatingPill: return 8
        case .physicalNotch: return 0
        }
    }

    private static func centeredFrame(size: CGSize, topOffset: CGFloat, screen: NSScreen) -> CGRect {
        let sf = screen.frame
        return CGRect(
            x: sf.midX - size.width / 2,
            y: sf.maxY - size.height - topOffset,
            width: size.width,
            height: size.height
        )
    }
}
