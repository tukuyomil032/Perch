import Testing

@testable import perch

@Suite("IslandPresentation")
@MainActor
struct IslandPresentationTests {
    @Test("expandsSurface is true for .expanded")
    func expandedExpandsSurface() {
        #expect(IslandPresentation.expanded(.nowPlaying).expandsSurface == true)
    }

    @Test("expandsSurface is true for .expanding")
    func expandingExpandsSurface() {
        #expect(IslandPresentation.expanding(.nowPlaying).expandsSurface == true)
    }

    @Test("expandsSurface is true for .collapsing — surface stays open during close animation")
    func collapsingExpandsSurface() {
        #expect(IslandPresentation.collapsing(.nowPlaying).expandsSurface == true)
    }

    @Test("expandsSurface is false for .compact")
    func compactDoesNotExpandSurface() {
        #expect(IslandPresentation.compact.expandsSurface == false)
    }

    @Test("showsExpandedDetails is true only for .expanded")
    func showsExpandedDetailsOnlyForExpanded() {
        #expect(IslandPresentation.expanded(.nowPlaying).showsExpandedDetails == true)
        #expect(IslandPresentation.expanding(.nowPlaying).showsExpandedDetails == false)
        #expect(IslandPresentation.collapsing(.nowPlaying).showsExpandedDetails == false)
        #expect(IslandPresentation.compact.showsExpandedDetails == false)
    }

    @Test("card is nil for .compact")
    func compactCardIsNil() {
        #expect(IslandPresentation.compact.card == nil)
    }

    @Test("card returns the associated IslandCard for .expanding")
    func expandingCardReturnsCard() {
        #expect(IslandPresentation.expanding(.nowPlaying).card == .nowPlaying)
    }

    @Test("card returns the associated IslandCard for .expanded")
    func expandedCardReturnsCard() {
        #expect(IslandPresentation.expanded(.nowPlaying).card == .nowPlaying)
    }

    @Test("card returns the associated IslandCard for .collapsing")
    func collapsingCardReturnsCard() {
        #expect(IslandPresentation.collapsing(.nowPlaying).card == .nowPlaying)
    }

    @Test("equatability — same cases are equal")
    func equatability() {
        #expect(IslandPresentation.expanding(.nowPlaying) == .expanding(.nowPlaying))
        #expect(IslandPresentation.expanded(.nowPlaying) == .expanded(.nowPlaying))
        #expect(IslandPresentation.collapsing(.nowPlaying) == .collapsing(.nowPlaying))
        #expect(IslandPresentation.compact == .compact)
    }

    @Test("equatability — different cases are not equal")
    func inequatability() {
        #expect(IslandPresentation.expanded(.nowPlaying) != .collapsing(.nowPlaying))
        #expect(IslandPresentation.expanded(.nowPlaying) != .compact)
        #expect(IslandPresentation.expanding(.nowPlaying) != .expanded(.nowPlaying))
    }
}
