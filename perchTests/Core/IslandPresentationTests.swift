import Testing

@testable import perch

@Suite("IslandPresentation")
@MainActor
struct IslandPresentationTests {
    @Test("expandsSurface is true for .expanded")
    func expandedExpandsSurface() {
        #expect(IslandPresentation.expanded(.nowPlaying).expandsSurface == true)
    }

    @Test("expandsSurface is false for .compact")
    func compactDoesNotExpandSurface() {
        #expect(IslandPresentation.compact.expandsSurface == false)
    }

    @Test("card is nil for .compact")
    func compactCardIsNil() {
        #expect(IslandPresentation.compact.card == nil)
    }

    @Test("card returns the associated IslandCard for .expanded")
    func expandedCardReturnsCard() {
        #expect(IslandPresentation.expanded(.nowPlaying).card == .nowPlaying)
    }

    @Test("equatability — same cases are equal")
    func equatability() {
        #expect(IslandPresentation.expanded(.nowPlaying) == .expanded(.nowPlaying))
        #expect(IslandPresentation.compact == .compact)
    }

    @Test("equatability — different cases and different cards are not equal")
    func inequatability() {
        #expect(IslandPresentation.expanded(.nowPlaying) != .compact)
        #expect(IslandPresentation.expanded(.nowPlaying) != .expanded(.aiUsage))
    }
}
