import SwiftUI

struct SessionListView: View {
    let sessions: [SessionSummary]

    @State private var isExpanded = false
    @State private var showContent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: {
                ExpandAnimation.toggle(
                    isExpanded: $isExpanded,
                    showContent: $showContent
                )
            }) {
                HStack {
                    Label("Active Sessions", systemImage: "bolt.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(sessions.count)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(ExpandAnimation.chevron, value: isExpanded)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Group {
                    if sessions.isEmpty {
                        Text("No active sessions")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.vertical, 4)
                    } else {
                        let content = VStack(spacing: 4) {
                            ForEach(sessions) { session in
                                SessionRow(session: session)
                            }
                        }
                        if sessions.count > 10 {
                            ScrollView { content }
                                .scrollIndicators(.never)
                                .frame(maxHeight: 250)
                        } else {
                            content
                        }
                    }
                }
                .opacity(showContent ? 1 : 0)
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct SessionRow: View {
    let session: SessionSummary

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "HH:mm"
        return f
    }()

    private var duration: String {
        let interval = Date().timeIntervalSince(session.startTime)
        let minutes = Int(interval) / 60
        if minutes < 1 { return "<1m" }
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if remainingMinutes == 0 { return "\(hours)h" }
        return "\(hours)h \(remainingMinutes)m"
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(.green)
                .frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.projectName)
                    .font(.caption)
                    .lineLimit(1)
                Text("\(Self.timeFormatter.string(from: session.startTime)) · \(duration)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Text(TokenFormatter.format(session.totalTokens))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
