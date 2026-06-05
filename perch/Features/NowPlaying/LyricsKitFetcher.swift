// perch/Features/NowPlaying/LyricsKitFetcher.swift
import Foundation
import Logging
import LyricsKit

actor LyricsKitFetcher {
    static let shared = LyricsKitFetcher()
    private let logger = Logger(label: "com.tukuyomi032.perch.LyricsKitFetcher")

    func fetch(title: String, artist: String) async -> [LyricsLine]? {
        // duration: 0 = no duration filter; match quality is slightly lower but still usable.
        // Future: pass NowPlayingState.duration here for better accuracy.
        let request = LyricsSearchRequest(
            searchTerm: .info(title: title, artist: artist),
            duration: 0
        )
        let providers: [any LyricsProvider] = [
            LyricsProviders.Service.netease.create(),
            LyricsProviders.Service.qq.create(),
            LyricsProviders.Service.kugou.create(),
        ]
        for provider in providers {
            if let lines = await fetchFromProvider(provider, request: request, expectedTitle: title) {
                return lines
            }
        }
        return nil
    }

    private func fetchFromProvider(
        _ provider: any LyricsProvider,
        request: LyricsSearchRequest,
        expectedTitle: String
    ) async -> [LyricsLine]? {
        do {
            for try await kitLyrics in provider.lyrics(for: request) {
                if let returnedTitle = kitLyrics.idTags[.title], !returnedTitle.isEmpty {
                    let norm1 = returnedTitle.lowercased()
                    let norm2 = expectedTitle.lowercased()
                    guard norm1.contains(norm2) || norm2.contains(norm1) else {
                        logger.debug(
                            "LyricsKitFetcher: skipping mismatched title '\(returnedTitle)' (expected '\(expectedTitle)')"
                        )
                        continue
                    }
                }
                let lines = kitLyrics.lines
                    .filter { $0.enabled && !$0.content.isEmpty }
                    .map { LyricsLine(timestamp: $0.position, text: $0.content) }
                if !lines.isEmpty {
                    if titleIsJapanese(expectedTitle) && !lyricsContainJapanese(lines) {
                        logger.debug("LyricsKitFetcher: skipping non-Japanese lyrics for '\(expectedTitle)'")
                        continue
                    }
                    logger.debug("LyricsKitFetcher: found \(lines.count) lines via \(type(of: provider))")
                    return lines
                }
            }
        } catch {
            logger.debug("LyricsKitFetcher: \(type(of: provider)) failed: \(error)")
        }
        return nil
    }

    private func titleIsJapanese(_ title: String) -> Bool {
        title.unicodeScalars.contains {
            ($0.value >= 0x3040 && $0.value <= 0x309F) || ($0.value >= 0x30A0 && $0.value <= 0x30FF)
        }
    }

    private func lyricsContainJapanese(_ lines: [LyricsLine]) -> Bool {
        lines.contains { line in
            line.text.unicodeScalars.contains {
                ($0.value >= 0x3040 && $0.value <= 0x309F) || ($0.value >= 0x30A0 && $0.value <= 0x30FF)
            }
        }
    }
}
