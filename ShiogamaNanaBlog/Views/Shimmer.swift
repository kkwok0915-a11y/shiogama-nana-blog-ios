import SwiftUI

/// A soft moving highlight. With Reduce Motion it stays a flat fill.
struct Shimmer: View {
    var cornerRadius: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -0.8

    var body: some View {
        Rectangle()
            .fill(Theme.inkSoft.opacity(0.12))
            .overlay {
                if !reduceMotion {
                    GeometryReader { proxy in
                        LinearGradient(
                            colors: [
                                .clear,
                                Theme.inkSoft.opacity(0.22),
                                .clear,
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: max(proxy.size.width * 0.55, 1))
                        .offset(x: phase * max(proxy.size.width, 1))
                    }
                    .clipped()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 1.4
                }
            }
            .accessibilityHidden(true)
    }
}
