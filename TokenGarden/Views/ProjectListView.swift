import SwiftUI

struct ProjectListView: View {
    let projects: [(name: String, tokens: Int)]
    @State private var isExpanded = false

    private var topProjects: [(name: String, tokens: Int)] {
        Array(projects.sorted { $0.tokens > $1.tokens }.prefix(3))
    }

    private var totalTokens: Int {
        projects.reduce(0) { $0 + $1.tokens }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("Projects", systemImage: "folder.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if !isExpanded {
                    Text("\(projects.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { withAnimation { isExpanded.toggle() } }

            let items = isExpanded ? projects.sorted(by: { $0.tokens > $1.tokens }) : topProjects
            ForEach(items, id: \.name) { project in
                HStack {
                    Text(project.name)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    let pct = totalTokens > 0 ? Int(Double(project.tokens) / Double(totalTokens) * 100) : 0
                    Text("\(pct)%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if !isExpanded && projects.count > 3 {
                Text("More...")
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .onTapGesture { withAnimation { isExpanded = true } }
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
