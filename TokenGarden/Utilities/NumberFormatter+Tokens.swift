import Foundation

enum TokenFormatter {
    static func format(_ value: Int) -> String {
        if value < 1000 {
            return "\(value)"
        } else if value < 1_000_000 {
            let k = Double(value) / 1000.0
            if k.truncatingRemainder(dividingBy: 1) == 0 {
                return "\(Int(k))K"
            }
            let formatted = String(format: "%.1fK", k)
            return formatted.replacingOccurrences(of: ".0K", with: "K")
        } else {
            let m = Double(value) / 1_000_000.0
            if m.truncatingRemainder(dividingBy: 1) == 0 {
                return "\(Int(m))M"
            }
            let formatted = String(format: "%.1fM", m)
            return formatted.replacingOccurrences(of: ".0M", with: "M")
        }
    }
}
