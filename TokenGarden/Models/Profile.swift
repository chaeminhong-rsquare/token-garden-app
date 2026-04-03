// TokenGarden/Models/Profile.swift
import Foundation
import SwiftData

enum PlanLimit {
    static let free = 500_000
    static let pro = 10_000_000
    static let max = 50_000_000

    static func defaultLimit(for plan: String) -> Int {
        switch plan.lowercased() {
        case "max": return max
        case "pro": return pro
        default: return free
        }
    }
}

@Model
class Profile {
    @Attribute(.unique) var name: String
    var email: String
    var plan: String
    var credentialsJSON: Data
    var isActive: Bool
    var createdAt: Date
    var monthlyLimit: Int

    init(name: String, email: String, plan: String, credentialsJSON: Data) {
        self.name = name
        self.email = email
        self.plan = plan
        self.credentialsJSON = credentialsJSON
        self.isActive = false
        self.createdAt = Date()
        self.monthlyLimit = PlanLimit.defaultLimit(for: plan)
    }
}
