// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Kai Azim - DynamicNotchKit (original)
// Copyright (c) 2026 Glendon Chin - OpenNook modifications
//
// Licensed under the MIT License.
// Original kit license: /ThirdPartyLicenses/DynamicNotchKit.txt
// Modifications license: /LICENSE-MIT-NOOKSURFACE
//
// Modified for Perch: added `.expandsOnHover` so hover-driven expansion can be turned
// off. Upstream expands unconditionally on hover with no way to opt out, which forecloses
// a design decision Perch wants to keep open.

import Foundation

/// Side-effects to apply while the cursor is over the nook chrome. Combine via option-set syntax.
public struct NookHoverBehavior: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Hover keeps the surface visible past hide animations.
    public static let keepVisible = NookHoverBehavior(rawValue: 1 << 0)

    /// Trigger a subtle alignment haptic on hover-state transitions.
    public static let hapticFeedback = NookHoverBehavior(rawValue: 1 << 1)

    /// Modified for Perch: hovering expands the surface, and leaving it compacts again.
    /// Without this option `isHovering` still updates, so a host can drive its own
    /// timing — which is what Perch does to honour its auto-collapse delay.
    public static let expandsOnHover = NookHoverBehavior(rawValue: 1 << 2)

    public static let all: NookHoverBehavior = [.keepVisible, .hapticFeedback, .expandsOnHover]
}
