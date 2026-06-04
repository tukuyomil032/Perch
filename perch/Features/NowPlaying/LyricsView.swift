// perch/Features/NowPlaying/LyricsView.swift
import SwiftUI

struct LyricsView: View {
    let lines: [LyricsLine]
    let elapsedTime: TimeInterval
    var fontSize: CGFloat = 13

    private var activeIndex: Int? {
        guard !lines.isEmpty else { return nil }
        for i in stride(from: lines.count - 1, through: 0, by: -1) {
            if elapsedTime >= lines[i].timestamp { return i }
        }
        return nil
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .center, spacing: 10) {
                    Color.clear.frame(height: 6)
                    ForEach(Array(lines.enumerated()), id: \.element.id) { idx, line in
                        Text(line.text)
                            .font(
                                .system(
                                    size: idx == activeIndex ? fontSize + 1 : fontSize,
                                    weight: idx == activeIndex ? .semibold : .regular)
                            )
                            .foregroundStyle(.white.opacity(lineOpacity(idx)))
                            .scaleEffect(idx == activeIndex ? 1.06 : 1.0, anchor: .center)
                            .multilineTextAlignment(.center)
                            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: activeIndex)
                            .id(line.id)
                    }
                    Color.clear.frame(height: 6)
                }
                .padding(.horizontal, 4)
            }
            .onChange(of: activeIndex) { _, newIdx in
                guard let newIdx else { return }
                withAnimation(.easeInOut(duration: 0.4)) {
                    proxy.scrollTo(lines[newIdx].id, anchor: UnitPoint(x: 0.5, y: 0.35))
                }
            }
            .onAppear {
                guard let idx = activeIndex else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    proxy.scrollTo(lines[idx].id, anchor: UnitPoint(x: 0.5, y: 0.35))
                }
            }
        }
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.05),
                    .init(color: .black, location: 0.92),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func lineOpacity(_ idx: Int) -> Double {
        guard let active = activeIndex else { return 0.38 }
        if idx == active { return 1.0 }
        let distance = abs(idx - active)
        if distance == 1 { return 0.55 }
        if distance == 2 { return 0.38 }
        return max(0.18, 0.30 - Double(distance - 3) * 0.05)
    }
}
