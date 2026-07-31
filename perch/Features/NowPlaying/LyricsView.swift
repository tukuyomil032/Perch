// perch/Features/NowPlaying/LyricsView.swift
import SwiftUI

struct LyricsView: View {
    let lines: [LyricsLine]
    let elapsedTime: TimeInterval
    var fontSize: CGFloat = 15

    private static let visibleLineCount = 4

    private var activeIndex: Int? {
        guard !lines.isEmpty else { return nil }
        for i in stride(from: lines.count - 1, through: 0, by: -1) {
            if elapsedTime >= lines[i].timestamp { return i }
        }
        return nil
    }

    /// Start of the fixed 4-line window shown on screen. A window, not a scroll
    /// position, so the column only ever renders whole lines — no partial fade-in/out
    /// line peeking past its edges the way a continuously-scrolled view would. Biases
    /// the active line to the window's second slot (one line of context above, two
    /// lines of what's coming below), clamping at both ends of `lines`.
    private var windowStart: Int {
        guard !lines.isEmpty else { return 0 }
        let count = min(Self.visibleLineCount, lines.count)
        let active = activeIndex ?? 0
        let desired = active - 1
        return max(0, min(desired, lines.count - count))
    }

    private var window: [(offset: Int, element: LyricsLine)] {
        let count = min(Self.visibleLineCount, lines.count)
        let start = windowStart
        return Array(Array(lines.enumerated())[start..<(start + count)])
    }

    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            ForEach(window, id: \.element.id) { idx, line in
                Text(line.text)
                    .font(.system(size: fontSize, weight: .regular))
                    .foregroundStyle(.white.opacity(lineOpacity(idx)))
                    .scaleEffect(idx == activeIndex ? 1.13 : 1.0, anchor: .center)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .animation(.spring(response: 0.55, dampingFraction: 0.82), value: activeIndex)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .id(windowStart)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
        .animation(.easeInOut(duration: 0.55), value: windowStart)
    }

    private func lineOpacity(_ idx: Int) -> Double {
        guard let active = activeIndex else { return 0.40 }
        if idx == active { return 1.0 }
        return abs(idx - active) == 1 ? 0.65 : 0.40
    }
}
