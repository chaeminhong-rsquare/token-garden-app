import SwiftUI

enum HeatmapTheme: String, CaseIterable {
    case green = "Green"
    case blue = "Blue"
    case purple = "Purple"
    case orange = "Orange"
    case red = "Red"
    case yellow = "Yellow"
    case pink = "Pink"
    case rainbow = "Rainbow"

    /// 8 colors: [0] = empty, [1..7] = intensity levels
    var colors: [Color] {
        let empty = Color(.systemGray).opacity(0.15)
        switch self {
        case .green:
            return [empty, .green.opacity(0.15), .green.opacity(0.25), .green.opacity(0.4),
                    .green.opacity(0.55), .green.opacity(0.7), .green.opacity(0.85), .green]
        case .blue:
            return [empty, .blue.opacity(0.15), .blue.opacity(0.25), .blue.opacity(0.4),
                    .blue.opacity(0.55), .blue.opacity(0.7), .blue.opacity(0.85), .blue]
        case .purple:
            return [empty, .purple.opacity(0.15), .purple.opacity(0.25), .purple.opacity(0.4),
                    .purple.opacity(0.55), .purple.opacity(0.7), .purple.opacity(0.85), .purple]
        case .orange:
            return [empty, .orange.opacity(0.15), .orange.opacity(0.25), .orange.opacity(0.4),
                    .orange.opacity(0.55), .orange.opacity(0.7), .orange.opacity(0.85), .orange]
        case .red:
            return [empty, .red.opacity(0.15), .red.opacity(0.25), .red.opacity(0.4),
                    .red.opacity(0.55), .red.opacity(0.7), .red.opacity(0.85), .red]
        case .yellow:
            return [empty, .yellow.opacity(0.15), .yellow.opacity(0.25), .yellow.opacity(0.4),
                    .yellow.opacity(0.55), .yellow.opacity(0.7), .yellow.opacity(0.85), .yellow]
        case .pink:
            return [empty, .pink.opacity(0.15), .pink.opacity(0.25), .pink.opacity(0.4),
                    .pink.opacity(0.55), .pink.opacity(0.7), .pink.opacity(0.85), .pink]
        case .rainbow:
            return [empty,
                    Color(hue: 0.7, saturation: 0.6, brightness: 0.9),
                    Color(hue: 0.58, saturation: 0.7, brightness: 0.9),
                    Color(hue: 0.45, saturation: 0.7, brightness: 0.85),
                    Color(hue: 0.33, saturation: 0.7, brightness: 0.8),
                    Color(hue: 0.15, saturation: 0.8, brightness: 0.95),
                    Color(hue: 0.08, saturation: 0.8, brightness: 0.95),
                    Color(hue: 0.0, saturation: 0.8, brightness: 0.9)]
        }
    }
}
