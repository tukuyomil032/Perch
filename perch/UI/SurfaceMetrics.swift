import CoreGraphics

/// Dimension constants for Rich mode's Home surface, collected in one place per
/// docs/macOS-Expanded-Surface-Layout-Handbook-ja.md §3 ("寸法を型にする") — magic
/// numbers scattered across views are how a 540pt width and a 260/300pt width end up
/// disagreeing with each other.
nonisolated enum SurfaceMetrics {
    /// The handbook's own basis (§0.1) is 640pt, sized for a fuller reference layout
    /// (Mirror included). Perch has no Mirror; 640 is kept anyway as the width that
    /// visibly closes the gap the user flagged against the reference mockup.
    static let baseContentWidth: CGFloat = 640
    static let minContentWidth: CGFloat = 480
    static let maxContentWidthFloor: CGFloat = 400
    static let maxContentWidthScreenInset: CGFloat = 60

    /// Content height floor for Rich mode's Home page (NowPlayingCard/CalendarMonthColumn
    /// on the left). Handbook §4.2 computes height per page from a Resolver; Perch's Home
    /// is a single page shape today, so this is that Resolver's one entry. Because the
    /// vendored `NookView` sizes itself via `.fixedSize()` (pure sizeToFit, no way for a
    /// window-side value to force a height), this is a **floor**, not an exact value —
    /// content taller than this still grows the shell. See `SurfaceSizeResolver`.
    static let homeContentHeightFloor: CGFloat = 260

    /// Rich mode's center column when it's showing lyrics (`NowPlayingLyricsColumn`) or
    /// today's events (`TodayEventsColumn`) — independent of whatever height the left
    /// column happens to measure at. ~4 lines of `LyricsView` text (13pt font, 10pt
    /// line spacing): `(13 * 1.3 + 10) * 4 ≈ 130pt`, where 13*1.3 approximates a single
    /// line's rendered height (font size × typical line-height multiplier).
    static let lyricsColumnHeight: CGFloat = 130
}
