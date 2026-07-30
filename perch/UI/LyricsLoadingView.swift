import SwiftUI

struct LyricsLoadingView: View {
    var body: some View {
        ProgressView()
            .controlSize(.small)
            .tint(.white.opacity(0.6))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}
