import Foundation

/// Value-type, Sendable snapshot of the data shown in the Overview tab.
///
/// The view layer only ever reads one of these — it never touches SwiftData
/// objects directly. This decouples UI from DB fetching and eliminates
/// SwiftData relationship faulting on the main thread when the popover opens.
struct OverviewSnapshot: Sendable, Equatable {
    var todayTokens: Int
    var weekTokens: Int
    var monthTokens: Int
    var heatmapData: [HeatmapCell]
    var hourlyTokens: [Int]              // 24-slot array, indexed by hour of day
    var todayProjects: [ProjectSummary]
    var weekProjects: [ProjectSummary]
    var monthProjects: [ProjectSummary]
    var activeSessions: [SessionSummary]
    var hasAnyData: Bool

    static let empty = OverviewSnapshot(
        todayTokens: 0,
        weekTokens: 0,
        monthTokens: 0,
        heatmapData: [],
        hourlyTokens: Array(repeating: 0, count: 24),
        todayProjects: [],
        weekProjects: [],
        monthProjects: [],
        activeSessions: [],
        hasAnyData: false
    )
}

/// Single heatmap cell data — detached from SwiftData's `DailyUsage`.
struct HeatmapCell: Sendable, Equatable, Hashable {
    let date: Date
    let tokens: Int
}

/// Project aggregate for a time range.
struct ProjectSummary: Sendable, Equatable, Hashable, Identifiable {
    let name: String
    let tokens: Int
    var id: String { name }
}

/// Active session summary — detached from SwiftData's `SessionUsage`.
struct SessionSummary: Sendable, Equatable, Hashable, Identifiable {
    let sessionId: String
    let projectName: String
    let startTime: Date
    let lastTime: Date
    let totalTokens: Int
    var id: String { sessionId }
}
