import AppKit

nonisolated struct ScreenEnvironment: Sendable {
    let frame: CGRect
    let visibleFrame: CGRect
    let safeAreaInsetsTop: CGFloat
    let auxiliaryTopLeftArea: CGRect?
    let auxiliaryTopRightArea: CGRect?
    let isBuiltIn: Bool
    let displayName: String

    var hasNotch: Bool {
        if auxiliaryTopLeftArea != nil, auxiliaryTopRightArea != nil { return true }
        return safeAreaInsetsTop > 0 && isBuiltIn
    }

    var notchSize: CGSize {
        if let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea {
            let notchWidth = frame.width - left.width - right.width
            let notchHeight = safeAreaInsetsTop
            if notchWidth > 0, notchHeight > 0 {
                return CGSize(width: notchWidth, height: notchHeight)
            }
        }
        if safeAreaInsetsTop > 0, isBuiltIn {
            return CGSize(width: 185, height: safeAreaInsetsTop)
        }
        return .zero
    }

    @MainActor
    static func live(screen: NSScreen) -> ScreenEnvironment {
        ScreenEnvironment(
            frame: screen.frame,
            visibleFrame: screen.visibleFrame,
            safeAreaInsetsTop: screen.safeAreaInsets.top,
            auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea,
            auxiliaryTopRightArea: screen.auxiliaryTopRightArea,
            isBuiltIn: screen.isBuiltInDisplay,
            displayName: screen.localizedName
        )
    }

    static func mockNotchedMacBook(frame: CGRect = CGRect(x: 0, y: 0, width: 1512, height: 982)) -> ScreenEnvironment {
        let notchWidth: CGFloat = 208
        let notchHeight: CGFloat = 38
        let sideWidth = (frame.width - notchWidth) / 2

        return ScreenEnvironment(
            frame: frame,
            visibleFrame: CGRect(
                x: frame.origin.x, y: frame.origin.y,
                width: frame.width, height: frame.height - notchHeight),
            safeAreaInsetsTop: notchHeight,
            auxiliaryTopLeftArea: CGRect(
                x: frame.origin.x,
                y: frame.origin.y + frame.height - notchHeight,
                width: sideWidth, height: notchHeight),
            auxiliaryTopRightArea: CGRect(
                x: frame.origin.x + sideWidth + notchWidth,
                y: frame.origin.y + frame.height - notchHeight,
                width: sideWidth, height: notchHeight),
            isBuiltIn: true,
            displayName: "Mock MacBook Notch"
        )
    }

    static func mockNonNotchedMac(frame: CGRect = CGRect(x: 0, y: 0, width: 1440, height: 900)) -> ScreenEnvironment {
        ScreenEnvironment(
            frame: frame,
            visibleFrame: CGRect(x: frame.origin.x, y: frame.origin.y, width: frame.width, height: frame.height - 24),
            safeAreaInsetsTop: 0,
            auxiliaryTopLeftArea: nil,
            auxiliaryTopRightArea: nil,
            isBuiltIn: false,
            displayName: "Mock Non-Notch Mac"
        )
    }
}
