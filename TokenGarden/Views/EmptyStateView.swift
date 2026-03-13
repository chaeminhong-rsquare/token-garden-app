import SwiftUI

enum EmptyStateReason {
    case noData
    case noPermission
    case noClaudeCode
}

struct EmptyStateView: View {
    let reason: EmptyStateReason

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if reason == .noPermission {
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var icon: String {
        switch reason {
        case .noData: "leaf.fill"
        case .noPermission: "lock.fill"
        case .noClaudeCode: "questionmark.folder.fill"
        }
    }

    private var title: String {
        switch reason {
        case .noData: "No Data Yet"
        case .noPermission: "Permission Required"
        case .noClaudeCode: "Logs Not Found"
        }
    }

    private var message: String {
        switch reason {
        case .noData:
            "Start using Claude Code and your token garden will grow here."
        case .noPermission:
            "Cannot access ~/.claude/ folder. Please grant permission in System Settings."
        case .noClaudeCode:
            "Claude Code log folder not found. Set the log path in Settings."
        }
    }
}
