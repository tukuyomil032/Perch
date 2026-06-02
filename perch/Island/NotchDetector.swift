import AppKit

extension NSScreen {
    var perchNotchSize: CGSize {
        guard let leftArea = auxiliaryTopLeftArea,
              let rightArea = auxiliaryTopRightArea else {
            return .zero
        }
        let notchWidth = frame.width - leftArea.width - rightArea.width
        let notchHeight = safeAreaInsets.top
        guard notchWidth > 0, notchHeight > 0 else { return .zero }
        return CGSize(width: notchWidth, height: notchHeight)
    }

    var isBuiltInDisplay: Bool {
        guard let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return false
        }
        return CGDisplayIsBuiltin(screenNumber) != 0
    }

    static var perchPreferredScreen: NSScreen? {
        // In headless environments, screens array may be empty or unavailable
        guard !NSScreen.screens.isEmpty else { return main }
        return NSScreen.screens.first(where: { $0.isBuiltInDisplay }) ?? main
    }
}
