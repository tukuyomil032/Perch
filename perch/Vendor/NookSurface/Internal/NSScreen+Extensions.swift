// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Kai Azim - DynamicNotchKit (original)
// Copyright (c) 2026 Glendon Chin - OpenNook modifications
//
// Licensed under the MIT License.
// Original kit license: /ThirdPartyLicenses/DynamicNotchKit.txt
// Modifications license: /LICENSE-MIT-NOOKSURFACE
//
// Modified for Perch: the synthetic notch width is a parameter instead of a hardcoded
// 300pt. Perch draws the notch shape on every Mac, including ones with no physical
// notch, so the fallback box has to be able to match real notch dimensions (185-208pt)
// rather than the testing-oriented placeholder upstream uses.

import SwiftUI

extension NSScreen {
    /// Heuristic - Apple notched displays expose auxiliary widths on both sides of the camera.
    var hasNotch: Bool {
        auxiliaryTopLeftArea?.width != nil && auxiliaryTopRightArea?.width != nil
    }

    /// Width-between-aux-areas / safe-area-top, when the screen actually has a notch.
    var notchSize: NSSize? {
        guard
            let topLeftPadding = auxiliaryTopLeftArea?.width,
            let topRightPadding = auxiliaryTopRightArea?.width
        else {
            return nil
        }

        let height = safeAreaInsets.top
        let width = frame.width - topLeftPadding - topRightPadding
        return NSSize(width: width, height: height)
    }

    /// Frame the chrome should hug. Centered horizontally, anchored to the top of the screen.
    var notchFrame: NSRect? {
        guard let notchSize else { return nil }
        return NSRect(
            x: frame.midX - (notchSize.width / 2),
            y: frame.maxY - notchSize.height,
            width: notchSize.width,
            height: notchSize.height
        )
    }

    var menubarHeight: CGFloat {
        frame.maxY - visibleFrame.maxY
    }

    /// Use `notchFrame` when available; otherwise center a box of `syntheticWidth` at the
    /// top so the surface still renders on displays with no physical notch.
    func notchFrameWithMenubarAsBackup(syntheticWidth: CGFloat) -> NSRect {
        if let notchFrame {
            return notchFrame
        }

        return NSRect(
            x: frame.midX - (syntheticWidth / 2),
            y: frame.maxY - menubarHeight,
            width: syntheticWidth,
            height: menubarHeight
        )
    }
}
