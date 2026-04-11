import SwiftUI

/// Pulse-animated skeleton placeholder. Used while data is loading for the
/// first time — subsequent refreshes show stale data instead so the
/// skeleton rarely (if ever) appears in normal use.
struct PulseSkeleton: View {
    var width: CGFloat? = nil
    var height: CGFloat = 14
    var cornerRadius: CGFloat = 4

    @State private var isPulsing = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.primary.opacity(isPulsing ? 0.06 : 0.14))
            .frame(width: width, height: height)
            .onAppear {
                guard !isPulsing else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}

/// Skeleton for the whole Overview tab. Rough layout matches the real UI
/// so the transition to real content doesn't jump.
struct OverviewSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Heatmap block
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Spacer()
                    PulseSkeleton(width: 110, height: 14, cornerRadius: 4)
                }
                PulseSkeleton(height: 132, cornerRadius: 6)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            // Stats block
            PulseSkeleton(height: 32, cornerRadius: 8)
                .padding(.horizontal, 12)

            // Hourly chart block
            PulseSkeleton(height: 32, cornerRadius: 8)
                .padding(.horizontal, 12)

            // Projects block
            PulseSkeleton(height: 32, cornerRadius: 8)
                .padding(.horizontal, 12)

            // Sessions block
            PulseSkeleton(height: 32, cornerRadius: 8)
                .padding(.horizontal, 12)
        }
        .padding(.bottom, 12)
    }
}
