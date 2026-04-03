// TokenGarden/Views/ProfileBannerView.swift
import SwiftUI
import SwiftData

struct ProfileBannerView: View {
    @EnvironmentObject var profileManager: ProfileManager
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            if let profile = profileManager.activeProfile {
                HStack(spacing: 8) {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(profile.name)
                            .font(.caption)
                            .fontWeight(.medium)
                        Text("\(profile.email) · \(profile.plan)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } else {
                HStack {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .foregroundStyle(.secondary)
                    Text("Add Profile")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
