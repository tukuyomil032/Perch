import Foundation
import Testing

@testable import perch

@Suite("LyricsNormalizer")
struct LyricsNormalizationTests {

    // MARK: - Title annotation stripping

    @Test("Strips (feat. X) suffix")
    func stripsFeaturingAnnotation() {
        #expect(LyricsNormalizer.stripTitleAnnotations("Song (feat. Artist B)") == "Song")
        #expect(LyricsNormalizer.stripTitleAnnotations("Song (feat. アーティストB)") == "Song")
        #expect(LyricsNormalizer.stripTitleAnnotations("Song (Feat. Artist B)") == "Song")
        #expect(LyricsNormalizer.stripTitleAnnotations("Song (ft. Artist B)") == "Song")
    }

    @Test("Strips (TV Size) / (Movie Version) / (Anime OP)")
    func stripsVersionAnnotations() {
        #expect(LyricsNormalizer.stripTitleAnnotations("曲名 (TV Size)") == "曲名")
        #expect(LyricsNormalizer.stripTitleAnnotations("Song (Movie Version)") == "Song")
        #expect(LyricsNormalizer.stripTitleAnnotations("Song (Anime OP)") == "Song")
        #expect(LyricsNormalizer.stripTitleAnnotations("Song (Radio Edit)") == "Song")
    }

    @Test("Strips [Remaster] / [Deluxe Edition] bracket annotations")
    func stripsBracketAnnotations() {
        #expect(LyricsNormalizer.stripTitleAnnotations("Song [Remaster]") == "Song")
        #expect(LyricsNormalizer.stripTitleAnnotations("Song [Deluxe Edition]") == "Song")
        #expect(LyricsNormalizer.stripTitleAnnotations("Song [2020 Remaster]") == "Song")
    }

    @Test("Strips trailing -Version- annotations")
    func stripsTrailingHyphenAnnotations() {
        #expect(LyricsNormalizer.stripTitleAnnotations("Song -TV Version-") == "Song")
        #expect(LyricsNormalizer.stripTitleAnnotations("Song -Original Mix-") == "Song")
    }

    @Test("Strips trailing - Remastered/Single/Extended Version")
    func stripsTrailingHyphenSuffix() {
        #expect(LyricsNormalizer.stripTitleAnnotations("Song - Remastered 2020") == "Song")
        #expect(LyricsNormalizer.stripTitleAnnotations("Song - Single Version") == "Song")
        #expect(LyricsNormalizer.stripTitleAnnotations("Song - Extended Mix") == "Song")
    }

    @Test("Leaves clean titles unchanged")
    func doesNotAlterCleanTitles() {
        #expect(LyricsNormalizer.stripTitleAnnotations("Song") == "Song")
        #expect(LyricsNormalizer.stripTitleAnnotations("曲名") == "曲名")
        #expect(LyricsNormalizer.stripTitleAnnotations("Song With Numbers 2024") == "Song With Numbers 2024")
    }

    // MARK: - Artist primary extraction

    @Test("Splits on ampersand")
    func splitsOnAmpersand() {
        #expect(LyricsNormalizer.primaryArtist("Artist A & Artist B") == "Artist A")
    }

    @Test("Splits on comma")
    func splitsOnComma() {
        #expect(LyricsNormalizer.primaryArtist("Artist A, Artist B") == "Artist A")
    }

    @Test("Splits on feat.")
    func splitsOnFeat() {
        #expect(LyricsNormalizer.primaryArtist("Artist A feat. Artist B") == "Artist A")
        #expect(LyricsNormalizer.primaryArtist("Artist A Feat. Artist B") == "Artist A")
        #expect(LyricsNormalizer.primaryArtist("Artist A ft. Artist B") == "Artist A")
    }

    @Test("Splits on 'with'")
    func splitsOnWith() {
        #expect(LyricsNormalizer.primaryArtist("Artist A with Artist B") == "Artist A")
    }

    @Test("Picks earliest separator when multiple present")
    func picksEarliestSeparator() {
        #expect(LyricsNormalizer.primaryArtist("Artist A & Artist B feat. Artist C") == "Artist A")
        #expect(LyricsNormalizer.primaryArtist("Artist A feat. B & C") == "Artist A")
    }

    @Test("Leaves single artist unchanged")
    func doesNotAlterSingleArtist() {
        #expect(LyricsNormalizer.primaryArtist("Solo Artist") == "Solo Artist")
        #expect(LyricsNormalizer.primaryArtist("アーティスト") == "アーティスト")
    }
}
