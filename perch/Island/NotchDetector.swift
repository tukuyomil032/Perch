import AppKit
import Logging

private let logger = Logger(label: "com.tukuyomi032.perch.NotchDetector")

extension NSScreen {
    var perchNotchSize: CGSize {
        if let leftArea = auxiliaryTopLeftArea, let rightArea = auxiliaryTopRightArea {
            let notchWidth = frame.width - leftArea.width - rightArea.width
            let notchHeight = safeAreaInsets.top
            if notchWidth > 0, notchHeight > 0 {
                logger.debug(
                    "notch detected via precise auxiliary areas",
                    metadata: [
                        "width": .stringConvertible(notchWidth),
                        "height": .stringConvertible(notchHeight),
                    ])
                return CGSize(width: notchWidth, height: notchHeight)
            }
        }

        if safeAreaInsets.top > 0, isBuiltInDisplay {
            logger.debug(
                "notch detected via fallback safeAreaInsets",
                metadata: [
                    "width": .stringConvertible(185),
                    "height": .stringConvertible(safeAreaInsets.top),
                ])
            return CGSize(width: 185, height: safeAreaInsets.top)
        }

        logger.debug("no notch detected")
        return .zero
    }

    var isBuiltInDisplay: Bool {
        guard let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        else {
            return false
        }
        return CGDisplayIsBuiltin(screenNumber) != 0
    }

    static var perchPreferredScreen: NSScreen? {
        // In headless environments, screens array may be empty or unavailable
        guard !NSScreen.screens.isEmpty else { return main }
        return NSScreen.screens.first(where: { $0.isBuiltInDisplay }) ?? main
    }

    static func logScreenDiagnostics() {
        logger.info(
            "screen diagnostics",
            metadata: [
                "screenCount": .stringConvertible(NSScreen.screens.count)
            ])
        for (index, screen) in NSScreen.screens.enumerated() {
            let leftDesc = screen.auxiliaryTopLeftArea.map { "\($0)" } ?? "nil"
            let rightDesc = screen.auxiliaryTopRightArea.map { "\($0)" } ?? "nil"
            logger.info(
                "screen[\(index)]",
                metadata: [
                    "name": .string(screen.localizedName),
                    "frame": .string("\(screen.frame)"),
                    "visibleFrame": .string("\(screen.visibleFrame)"),
                    "isBuiltIn": .stringConvertible(screen.isBuiltInDisplay),
                    "safeAreaInsets.top": .stringConvertible(screen.safeAreaInsets.top),
                    "auxiliaryTopLeftArea": .string(leftDesc),
                    "auxiliaryTopRightArea": .string(rightDesc),
                ])
        }
        let preferred = NSScreen.perchPreferredScreen
        logger.info(
            "perchPreferredScreen selected",
            metadata: [
                "name": .string(preferred?.localizedName ?? "nil")
            ])
        if let preferred {
            let notchSize = preferred.perchNotchSize
            logger.info(
                "perchNotchSize for preferred screen",
                metadata: [
                    "width": .stringConvertible(notchSize.width),
                    "height": .stringConvertible(notchSize.height),
                ])
        }
    }
}
