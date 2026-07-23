// perch/Features/NowPlaying/LyricsKitFetcher.swift
import Foundation
import Logging
import LyricsKit

actor LyricsKitFetcher {
    static let shared = LyricsKitFetcher()
    private let logger = Logger(label: "com.tukuyomi032.perch.LyricsKitFetcher")

    private static let perProviderTimeoutSeconds: Double = 3.0

    func fetch(title: String, artist: String) async -> [LyricsLine]? {
        let request = LyricsSearchRequest(
            searchTerm: .info(title: title, artist: artist),
            duration: 0
        )
        let providers: [any LyricsProvider] = [
            LyricsProviders.Service.netease.create(),
            LyricsProviders.Service.qq.create(),
            LyricsProviders.Service.kugou.create(),
        ]
        logger.info(
            "LyricsKitFetcher: racing \(providers.count) providers for '\(title)' by '\(artist)'"
        )

        // Race all providers in parallel. First non-empty result wins; the
        // rest are cancelled. Each provider has its own 3s timeout so a slow
        // one can't block the others.
        return await withTaskGroup(of: [LyricsLine]?.self) { group in
            for provider in providers {
                group.addTask {
                    await self.timedProviderFetch(
                        provider: provider,
                        request: request,
                        expectedTitle: title
                    )
                }
            }
            for await result in group {
                if let lines = result, !lines.isEmpty {
                    group.cancelAll()
                    return lines
                }
            }
            return nil
        }
    }

    private func timedProviderFetch(
        provider: any LyricsProvider,
        request: LyricsSearchRequest,
        expectedTitle: String
    ) async -> [LyricsLine]? {
        let providerName = String(describing: type(of: provider))
        return await withTaskGroup(of: [LyricsLine]?.self) { inner in
            inner.addTask {
                await self.fetchFromProvider(
                    provider, request: request, expectedTitle: expectedTitle,
                    providerName: providerName)
            }
            inner.addTask {
                try? await Task.sleep(for: .seconds(Self.perProviderTimeoutSeconds))
                await self.logTimeout(providerName)
                return nil
            }
            let first = await inner.next()
            inner.cancelAll()
            return first ?? nil
        }
    }

    private func logTimeout(_ providerName: String) {
        logger.debug("LyricsKitFetcher: \(providerName) timed out after \(Self.perProviderTimeoutSeconds)s")
    }

    private func fetchFromProvider(
        _ provider: any LyricsProvider,
        request: LyricsSearchRequest,
        expectedTitle: String,
        providerName: String
    ) async -> [LyricsLine]? {
        do {
            for try await kitLyrics in provider.lyrics(for: request) {
                if let returnedTitle = kitLyrics.idTags[.title], !returnedTitle.isEmpty {
                    let norm1 = returnedTitle.lowercased()
                    let norm2 = expectedTitle.lowercased()
                    guard norm1.contains(norm2) || norm2.contains(norm1) else {
                        logger.debug(
                            "LyricsKitFetcher/\(providerName): skipping mismatched title '\(returnedTitle)' (expected '\(expectedTitle)')"
                        )
                        continue
                    }
                }
                let lines =
                    kitLyrics.lines
                    .filter { $0.enabled && !$0.content.isEmpty }
                    .map { LyricsLine(timestamp: $0.position, text: $0.content) }
                if !lines.isEmpty {
                    // Guard against Chinese providers returning Chinese lyrics for
                    // Japanese songs. Trigger the guard when the title CONTAINS ANY
                    // Japanese-script character (hiragana/katakana or CJK ideograph
                    // — kanji-only邦楽 titles must still enforce the check).
                    // Accept the result only if the lyrics contain hiragana or
                    // katakana; kanji alone is ambiguous between Japanese and Chinese.
                    if titleContainsJapaneseScript(expectedTitle),
                        !lyricsContainKana(lines)
                    {
                        logger.debug(
                            "LyricsKitFetcher/\(providerName): skipping non-Japanese lyrics for '\(expectedTitle)'"
                        )
                        continue
                    }
                    logger.info(
                        "LyricsKitFetcher/\(providerName): found \(lines.count) lines for '\(expectedTitle)'"
                    )
                    return lines
                }
            }
        } catch {
            logger.debug("LyricsKitFetcher/\(providerName): failed: \(error)")
        }
        return nil
    }

    /// True if the title contains hiragana, katakana, or CJK Unified Ideographs.
    /// The CJK block covers 漢字 that Japanese titles frequently use in isolation
    /// (e.g. `"鬼滅の刃"`, `"薬指"` — hiragana or kanji-only lines both count).
    private nonisolated func titleContainsJapaneseScript(_ title: String) -> Bool {
        title.unicodeScalars.contains { scalar in
            (0x3040...0x309F).contains(scalar.value)  // Hiragana
                || (0x30A0...0x30FF).contains(scalar.value)  // Katakana
                || (0x4E00...0x9FFF).contains(scalar.value)  // CJK Unified Ideographs (Kanji)
        }
    }

    /// True if the lyrics contain hiragana or katakana — an unambiguous signal
    /// of Japanese (Chinese lyric providers never emit these scripts).
    private nonisolated func lyricsContainKana(_ lines: [LyricsLine]) -> Bool {
        lines.contains { line in
            line.text.unicodeScalars.contains { scalar in
                (0x3040...0x309F).contains(scalar.value)  // Hiragana
                    || (0x30A0...0x30FF).contains(scalar.value)  // Katakana
            }
        }
    }
}
