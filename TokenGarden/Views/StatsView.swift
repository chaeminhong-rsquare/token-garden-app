import SwiftUI

struct StatsView: View {
    let todayTokens: Int
    let weekTokens: Int
    let monthTokens: Int
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("Today", systemImage: "chart.bar.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(TokenFormatter.format(todayTokens))
                    .font(.caption.monospacedDigit())
                    .fontWeight(.medium)
                Text(TokenFormatter.format(weekTokens))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture { withAnimation { isExpanded.toggle() } }

            if isExpanded {
                HStack {
                    VStack(alignment: .leading) {
                        Text("This Week").font(.caption2).foregroundStyle(.secondary)
                        Text(TokenFormatter.format(weekTokens)).font(.caption.monospacedDigit())
                    }
                    Spacer()
                    VStack(alignment: .leading) {
                        Text("This Month").font(.caption2).foregroundStyle(.secondary)
                        Text(TokenFormatter.format(monthTokens)).font(.caption.monospacedDigit())
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
