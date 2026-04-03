// TokenGarden/Models/ProfileTokenUsage.swift
import Foundation
import SwiftData

@Model
class ProfileTokenUsage {
    var profileName: String
    var date: Date
    var tokens: Int

    init(profileName: String, date: Date, tokens: Int = 0) {
        self.profileName = profileName
        self.date = date
        self.tokens = tokens
    }
}
