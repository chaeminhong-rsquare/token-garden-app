import Foundation
import SwiftData

@Model
class HourlyUsage {
    var date: Date
    var hour: Int
    var tokens: Int

    init(date: Date, hour: Int, tokens: Int = 0) {
        self.date = date
        self.hour = hour
        self.tokens = tokens
    }
}
