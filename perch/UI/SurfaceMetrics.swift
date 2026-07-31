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
    /// column happens to measure at. ~4 lines of `LyricsView` text (15pt font, 10pt
    /// line spacing): `(15 * 1.3 + 10) * 4 ≈ 118pt`, where 15*1.3 approximates a single
    /// line's rendered height (font size × typical line-height multiplier); 130 keeps a
    /// little slack over that estimate.
    static let lyricsColumnHeight: CGFloat = 130

    /// `IslandTopBar`'s own rendered height (10pt top padding + 26pt tallest control +
    /// 8pt bottom padding = 44pt) plus the hairline `Divider` `ExpandedIslandView` draws
    /// below it. An approximation from the source, not a measurement — used only to
    /// compensate `RichHomeView`'s lyrics/events column centering for the header sitting
    /// above the row it's actually centered against (see `RichHomeView`).
    static let headerHeight: CGFloat = 45
}
