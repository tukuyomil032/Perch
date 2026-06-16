import SwiftUI

struct LyricsLoadingView: View {
    var body: some View {
        TimelineView(.animation) { ctx in
            Canvas { context, size in
                let t = ctx.date.timeIntervalSince1970
                for i in 0..<3 {
                    let phase = Double(i) * .pi * 2.0 / 3.0
                    var path = Path()
                    var x = 0.0
                    var isFirst = true
                    while x <= size.width {
                        let y = size.height / 2 + sin(x / 28 + t * 2.5 + phase) * 7
                        if isFirst {
                            path.move(to: .init(x: x, y: y))
                            isFirst = false
                        } else {
                            path.addLine(to: .init(x: x, y: y))
                        }
                        x += 2
                    }
                    context.stroke(
                        path,
                        with: .color(.white.opacity(0.50 - Double(i) * 0.13)),
                        lineWidth: 1.5
                    )
                }
            }
        }
        .frame(height: 30)
        .frame(maxWidth: .infinity)
    }
}
