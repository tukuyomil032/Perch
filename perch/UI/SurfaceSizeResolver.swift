import CoreGraphics

/// Resolves Rich mode's Home content target size from screen width, per
/// docs/macOS-Expanded-Surface-Layout-Handbook-ja.md §4 ("Size Resolver") — one pure
/// function both the window floor (`ExpandedIslandView`) and the content layout
/// (`RichHomeView`) read, instead of each carrying its own hardcoded number.
///
/// `PageKind` has one case today because Rich mode has one page shape (Home). The
/// handbook's Resolver switches on several page kinds (Timer, Notes, Terminal, ...);
/// this is that same shape scaled down, ready to grow a case per page as Perch adds
/// them (File Shelf, Timer).
nonisolated enum SurfaceSizeResolver {
    enum PageKind {
        case richHome
    }

    struct Input {
        let page: PageKind
        let screenWidth: CGFloat
    }

    struct Output: Equatable {
        let contentMinWidth: CGFloat
        /// A floor, not an exact target — see `SurfaceMetrics.homeContentHeightFloor`.
        let contentHeightFloor: CGFloat
    }

    static func resolve(_ input: Input) -> Output {
        let maxWidth = max(
            SurfaceMetrics.maxContentWidthFloor,
            input.screenWidth - SurfaceMetrics.maxContentWidthScreenInset
        )
        let width = min(
            max(SurfaceMetrics.baseContentWidth, SurfaceMetrics.minContentWidth),
            maxWidth
        )

        let height: CGFloat
        switch input.page {
        case .richHome:
            height = SurfaceMetrics.homeContentHeightFloor
        }

        return Output(contentMinWidth: width, contentHeightFloor: height)
    }
}
