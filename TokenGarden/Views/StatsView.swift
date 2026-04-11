import SwiftUI

struct StatsView: View {
    let todayTokens: Int
    let weekTokens: Int
    let monthTokens: Int
    @State private var isExpanded = false
    @State private var showContent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Stats", systemImage: "chart.bar.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if !isExpanded {
                    Text(TokenFormatter.format(todayTokens))
                        .font(.caption.monospacedDigit())
                        .fontWeight(.medium)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(ExpandAnimation.chevron, value: isExpanded)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                ExpandAnimation.toggle(
                    isExpanded: $isExpanded,
                    showContent: $showContent
                )
            }

            if isExpanded {
                VStack(spacing: 6) {
                    statsRow(label: "Today", value: todayTokens)
                    statsRow(label: "This Week", value: weekTokens)
                    statsRow(label: "This Month", value: monthTokens)
                }
                .opacity(showContent ? 1 : 0)
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func statsRow(label: String, value: Int) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(TokenFormatter.format(value))
                .font(.caption.monospacedDigit())
                .fontWeight(.medium)
        }
    }
}
