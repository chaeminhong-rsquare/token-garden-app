import Foundation
import SwiftData

/// Background SwiftData worker that produces `OverviewSnapshot` value objects.
///
/// Uses the `@ModelActor` macro so all fetches run on the actor's executor —
/// never blocking the main thread. Callers await the result and receive
/// Sendable values, so SwiftData entities never leak into the UI layer.
@ModelActor
actor OverviewRepository {
    /// Fetch everything the Overview tab needs and roll it up into a
    /// `Sendable` value type. Relationship faulting happens here on the
    /// background executor, so the main thread never pays for it.
    func loadSnapshot(referenceDate: Date = Date()) -> OverviewSnapshot {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: referenceDate)

        var weekCal = calendar
        weekCal.firstWeekday = 2
        let weekStart = weekCal.dateComponents(
            [.calendar, .yearForWeekOfYear, .weekOfYear],
            from: referenceDate
        ).date ?? today

        let monthComps = calendar.dateComponents([.year, .month], from: referenceDate)
        let monthStart = calendar.date(from: monthComps) ?? today

        // 1. Daily usages (drives heatmap, stats, project breakdowns)
        var dailyDescriptor = FetchDescriptor<DailyUsage>()
        dailyDescriptor.sortBy = [SortDescriptor(\DailyUsage.date)]
        let dailies = (try? modelContext.fetch(dailyDescriptor)) ?? []

        var todayTokens = 0
        var weekTokens = 0
        var monthTokens = 0
        var heatmapData: [HeatmapCell] = []
        heatmapData.reserveCapacity(dailies.count)

        var todayProjectTotals: [String: Int] = [:]
        var weekProjectTotals: [String: Int] = [:]
        var monthProjectTotals: [String: Int] = [:]

        for daily in dailies {
            let dailyTotal = daily.totalTokens
            heatmapData.append(HeatmapCell(date: daily.date, tokens: dailyTotal))

            if daily.date == today { todayTokens = dailyTotal }
            if daily.date >= weekStart { weekTokens += dailyTotal }
            if daily.date >= monthStart { monthTokens += dailyTotal }

            // Relationship faulting happens on background executor — safe.
            for project in daily.projectBreakdowns {
                let name = project.projectName
                let t = project.tokens
                if daily.date == today {
                    todayProjectTotals[name, default: 0] += t
                }
                if daily.date >= weekStart {
                    weekProjectTotals[name, default: 0] += t
                }
                if daily.date >= monthStart {
                    monthProjectTotals[name, default: 0] += t
                }
            }
        }

        // 2. Hourly tokens for today (reuses same logic as loadHourlyTokens)
        let hourlyTokens = loadHourlyTokens(for: today)

        // 3. Active sessions
        var sessionDescriptor = FetchDescriptor<SessionUsage>(
            predicate: #Predicate<SessionUsage> { $0.isActive == true }
        )
        sessionDescriptor.sortBy = [SortDescriptor(\SessionUsage.lastTime, order: .reverse)]
        let sessions = (try? modelContext.fetch(sessionDescriptor)) ?? []
        let activeSessions = sessions.map {
            SessionSummary(
                sessionId: $0.sessionId,
                projectName: $0.projectName,
                startTime: $0.startTime,
                lastTime: $0.lastTime,
                totalTokens: $0.totalTokens
            )
        }

        return OverviewSnapshot(
            todayTokens: todayTokens,
            weekTokens: weekTokens,
            monthTokens: monthTokens,
            heatmapData: heatmapData,
            hourlyTokens: hourlyTokens,
            todayProjects: todayProjectTotals.map { ProjectSummary(name: $0.key, tokens: $0.value) },
            weekProjects: weekProjectTotals.map { ProjectSummary(name: $0.key, tokens: $0.value) },
            monthProjects: monthProjectTotals.map { ProjectSummary(name: $0.key, tokens: $0.value) },
            activeSessions: activeSessions,
            hasAnyData: !dailies.isEmpty
        )
    }

    /// Hourly tokens for a specific day — used when the user selects a date
    /// in the heatmap.
    func loadHourlyTokens(for date: Date) -> [Int] {
        let day = Calendar.current.startOfDay(for: date)
        let descriptor = FetchDescriptor<HourlyUsage>(
            predicate: #Predicate { $0.date == day }
        )
        let entries = (try? modelContext.fetch(descriptor)) ?? []
        var buckets = Array(repeating: 0, count: 24)
        for entry in entries where entry.hour >= 0 && entry.hour < 24 {
            buckets[entry.hour] += entry.tokens
        }
        return buckets
    }

    /// Project breakdown for a specific day.
    func loadProjects(for date: Date) -> [ProjectSummary] {
        let day = Calendar.current.startOfDay(for: date)
        let descriptor = FetchDescriptor<DailyUsage>(
            predicate: #Predicate { $0.date == day }
        )
        let dailies = (try? modelContext.fetch(descriptor)) ?? []
        var totals: [String: Int] = [:]
        for daily in dailies {
            for project in daily.projectBreakdowns {
                totals[project.projectName, default: 0] += project.tokens
            }
        }
        return totals.map { ProjectSummary(name: $0.key, tokens: $0.value) }
    }
}
