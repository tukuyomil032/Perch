// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in this repository (Perch is itself Apache-2.0
// licensed, so this file's terms match the project's own root license).
// Attribution: THIRD_PARTY_NOTICES.md.
//
// Modified for Perch: renamed `NookScreenLocator` -> `ScreenLocator` (the `Nook`
// prefix is redundant once the type lives in Perch's own module; see CLAUDE.md's
// "no `Perch` prefix" convention applied in reverse). Renamed `NookDisplayPreference`
// -> `ScreenPreference` and inlined it into this file: upstream's version also carries
// `NookDisplayStore`, a UserDefaults-backed persistence layer built on
// `NookPreferenceStorage`, a NookKit-only type. Perch persists preferences through the
// `Defaults` package (see `perch/Core/Preferences.swift`), not a hand-rolled JSON
// blob store, so that persistence layer was dropped rather than copied - carrying it
// over would have pulled in a second, incompatible persistence convention for no
// current caller. `ScreenPreference` keeps upstream's `Codable` conformance so a
// future `Defaults.Key<ScreenPreference>` (Phase A5, when this type is actually wired
// up) doesn't require touching this file again. Dropped every `public` access
// modifier (`public enum` -> `enum`, `public struct` -> `struct`, `public let`/`var`/
// `static func`/`init` -> internal) since both types are internal to the Perch module,
// with no cross-module consumer the way NookKit had one. Added `nonisolated` to
// `ScreenPreference` and `ScreenLocator` themselves: Perch's project settings default
// every declaration to `@MainActor` (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`),
// which upstream's package doesn't set, so without `nonisolated` neither type's pure,
// synchronous API (notably `resolveIndex`) could be called from a plain test function.

import AppKit
import CoreGraphics

/// Which display the Island chrome should appear on.
///
/// A notch app's chrome is physically tied to a screen, but on a multi-display Mac
/// "which screen" is a real choice. This expresses that choice in a form that
/// survives reboots and display reconfiguration:
///
/// - ``Mode/builtIn`` - the laptop's built-in (notched) panel. The default: a notch
///   app's chrome belongs where the physical notch is.
/// - ``Mode/main`` - whichever display currently hosts the active menu bar
///   (`NSScreen.main`). Follows the user's focus across screens.
/// - ``Mode/specific`` - a single named display, pinned by its stable display UUID
///   (``displayUUID``). Survives unplug/replug and arrangement changes.
///
/// Resolving a preference to a concrete `NSScreen` is ``ScreenLocator``'s job; it
/// falls back gracefully when the chosen display isn't currently attached.
nonisolated struct ScreenPreference: Equatable, Codable, Sendable {
    enum Mode: String, Codable, Sendable, CaseIterable {
        case builtIn
        case main
        case specific
    }

    var mode: Mode

    /// Stable display UUID, used only when ``mode`` is ``Mode/specific``. `nil` for the
    /// built-in / main modes. The UUID comes from `CGDisplayCreateUUIDFromDisplayID`
    /// and is stable across reconnects, unlike the transient `CGDirectDisplayID`.
    var displayUUID: String?

    init(mode: Mode, displayUUID: String? = nil) {
        self.mode = mode
        self.displayUUID = displayUUID
    }

    /// The built-in (notched) display. A notch app's chrome belongs on the notch.
    static let builtIn = ScreenPreference(mode: .builtIn)

    /// The display currently hosting the active menu bar (`NSScreen.main`).
    static let main = ScreenPreference(mode: .main)

    /// A single display pinned by its stable display UUID.
    static func specific(_ uuid: String) -> ScreenPreference {
        ScreenPreference(mode: .specific, displayUUID: uuid)
    }

    static let `default` = ScreenPreference.builtIn

    private enum CodingKeys: String, CodingKey {
        case mode
        case displayUUID
    }

    // Lenient decode so JSON from an older/newer build round-trips to a sane value
    // instead of failing the whole record. An unrecognized `mode` string, or a
    // `.specific` mode missing its UUID, both degrade to the default rather than throw.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawMode = try container.decodeIfPresent(String.self, forKey: .mode)
        let uuid = try container.decodeIfPresent(String.self, forKey: .displayUUID)
        guard let rawMode, let mode = Mode(rawValue: rawMode) else {
            self = .default
            return
        }
        if mode == .specific, uuid == nil {
            self = .default
            return
        }
        self.init(mode: mode, displayUUID: uuid)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mode, forKey: .mode)
        try container.encodeIfPresent(displayUUID, forKey: .displayUUID)
    }
}

/// Resolves a ``ScreenPreference`` to a concrete `NSScreen`, and enumerates the
/// attached displays for settings UI.
///
/// The tricky part of multi-display support is *stable* identity: `CGDirectDisplayID`
/// and `NSScreen` ordering both shuffle as displays connect and disconnect, so a saved
/// preference can't reference them directly. The display *UUID*
/// (`CGDisplayCreateUUIDFromDisplayID`) is stable across reconnects, so that's what
/// ``ScreenPreference/specific(_:)`` persists and what this type matches against.
nonisolated enum ScreenLocator {
    /// A currently-attached display, as surfaced to settings UI.
    struct DisplayInfo: Identifiable, Equatable, Sendable {
        /// Stable display UUID - the value stored in ``ScreenPreference``.
        let uuid: String
        /// Human-readable name (`NSScreen.localizedName`), e.g. "Built-in Retina Display".
        let name: String
        /// `true` for the Mac's built-in panel.
        let isBuiltIn: Bool

        var id: String { uuid }
    }

    /// The `CGDirectDisplayID` backing a screen. Transient - valid only for the current
    /// display arrangement; never persist it.
    static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber)?.uint32Value
    }

    /// Stable UUID string for a display ID, surviving unplug/replug. `nil` for the rare
    /// display that exposes no UUID (some virtual/streamed displays).
    static func uuid(for displayID: CGDirectDisplayID) -> String? {
        guard let cfUUID = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else {
            return nil
        }
        return CFUUIDCreateString(nil, cfUUID) as String
    }

    /// Stable UUID string for a screen.
    static func uuid(for screen: NSScreen) -> String? {
        guard let id = displayID(for: screen) else { return nil }
        return uuid(for: id)
    }

    /// Every currently-attached display, for populating a display picker.
    static func connectedDisplays() -> [DisplayInfo] {
        NSScreen.screens.compactMap { screen in
            guard let id = displayID(for: screen), let uuid = uuid(for: id) else { return nil }
            return DisplayInfo(
                uuid: uuid,
                name: screen.localizedName,
                isBuiltIn: CGDisplayIsBuiltin(id) != 0
            )
        }
    }

    /// A display abstracted to just what the fallback chain needs, so the resolution
    /// *policy* can be unit-tested without a live `NSScreen` (which is unavailable on
    /// headless CI). The AppKit path builds these from `NSScreen.screens`.
    struct DisplayCandidate: Equatable, Sendable {
        /// Stable display UUID, or `nil` for displays that expose none.
        let uuid: String?
        /// `true` for the Mac's built-in panel.
        let isBuiltIn: Bool

        init(uuid: String?, isBuiltIn: Bool) {
            self.uuid = uuid
            self.isBuiltIn = isBuiltIn
        }
    }

    /// Pure fallback-chain policy: pick the index into `displays` that satisfies
    /// `preference`, degrading rather than vanishing when the chosen display is gone.
    ///
    /// - `.specific`: the matching UUID, else built-in -> main -> first.
    /// - `.builtIn`: built-in -> main -> first.
    /// - `.main`: main -> built-in -> first.
    ///
    /// Returns `nil` only when `displays` is empty. `mainIndex` is the index of the
    /// system's main display within `displays` (the AppKit path derives it from
    /// `NSScreen.main`); `nil` if unknown.
    static func resolveIndex(
        preference: ScreenPreference,
        displays: [DisplayCandidate],
        mainIndex: Int?
    ) -> Int? {
        guard !displays.isEmpty else { return nil }
        let builtInIndex = displays.firstIndex { $0.isBuiltIn }
        let builtInThenMainThenFirst = builtInIndex ?? mainIndex ?? 0

        switch preference.mode {
        case .specific:
            if let uuid = preference.displayUUID,
                let match = displays.firstIndex(where: { $0.uuid == uuid })
            {
                return match
            }
            return builtInThenMainThenFirst
        case .builtIn:
            return builtInThenMainThenFirst
        case .main:
            return mainIndex ?? builtInIndex ?? 0
        }
    }

    /// Resolve a preference to a concrete screen.
    ///
    /// The fallback chain keeps the chrome on-screen even when the chosen display is
    /// unplugged: a `.specific` display that isn't attached, or a `.builtIn` request on a
    /// desktop Mac, both degrade to built-in -> main -> first-attached rather than vanishing.
    /// Returns `nil` only when no display is attached at all. The policy lives in
    /// ``resolveIndex(preference:displays:mainIndex:)`` so it stays testable headlessly.
    static func screen(matching preference: ScreenPreference) -> NSScreen? {
        let screens = NSScreen.screens
        let candidates = screens.map { DisplayCandidate(uuid: Self.uuid(for: $0), isBuiltIn: isBuiltIn($0)) }
        let mainIndex = NSScreen.main.flatMap { screens.firstIndex(of: $0) }
        guard let index = resolveIndex(preference: preference, displays: candidates, mainIndex: mainIndex) else {
            return nil
        }
        return screens[index]
    }

    /// Whether a screen is the Mac's built-in panel.
    private static func isBuiltIn(_ screen: NSScreen) -> Bool {
        guard let id = displayID(for: screen) else { return false }
        return CGDisplayIsBuiltin(id) != 0
    }

    /// The Mac's built-in panel, if one is attached.
    static func builtInScreen() -> NSScreen? {
        NSScreen.screens.first(where: isBuiltIn)
    }
}
