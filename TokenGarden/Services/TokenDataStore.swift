import Foundation
import SwiftData

@MainActor
class TokenDataStore: ObservableObject {
    private let modelContainer: ModelContainer
    private let modelContext: ModelContext
    private let cache = RecordCache()
    private var pendingSaveCount = 0
    var activeProfileName: String?
    private static let saveInterval = 10

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        self.modelContext = modelContainer.mainContext
    }

    func record(_ event: TokenEvent) {
        cache.invalidateIfNeeded(for: event.timestamp)

        let day = Calendar.current.startOfDay(for: event.timestamp)
        let daily = cache.getOrCreateDaily(day: day, in: modelContext)

        daily.inputTokens += event.inputTokens
        daily.outputTokens += event.outputTokens
        daily.cacheCreationTokens += event.cacheCreationTokens
        daily.cacheReadTokens += event.cacheReadTokens

        // Hourly bucket
        let hour = Calendar.current.component(.hour, from: event.timestamp)
        let hourly = cache.getOrCreateHourly(day: day, hour: hour, in: modelContext)
        hourly.tokens += event.totalTokens

        // Project breakdown — in-memory traversal of daily.projectBreakdowns (no fetch)
        if let projectName = event.projectName {
            let profile = activeProfileName
            if let existing = daily.projectBreakdowns.first(where: {
                $0.projectName == projectName && $0.profileName == profile
            }) {
                existing.tokens += event.totalTokens
            } else {
                let projectUsage = ProjectUsage(
                    projectName: projectName,
                    tokens: event.totalTokens,
                    model: event.model,
                    profileName: profile
                )
                projectUsage.dailyUsage = daily
                daily.projectBreakdowns.append(projectUsage)
            }
        }

        // Profile token tracking
        if let profileName = activeProfileName {
            let profileUsage = cache.getOrCreateProfileToken(
                profileName: profileName,
                day: day,
                in: modelContext
            )
            profileUsage.tokens += event.totalTokens
        }

        // Session tracking
        if let sessionId = event.sessionId {
            let session = cache.getOrCreateSession(
                sessionId: sessionId,
                projectName: event.projectName ?? "Unknown",
                timestamp: event.timestamp,
                in: modelContext
            )
            session.totalTokens += event.totalTokens
            session.lastTime = event.timestamp
        }

        pendingSaveCount += 1
        if pendingSaveCount >= Self.saveInterval {
            try? modelContext.save()
            pendingSaveCount = 0
        }
    }

    func endSession(sessionId: String) {
        let descriptor = FetchDescriptor<SessionUsage>(
            predicate: #Predicate { $0.sessionId == sessionId }
        )
        if let session = try? modelContext.fetch(descriptor).first {
            session.isActive = false
        }
    }

    /// Apply active status with pre-fetched project names. Must be called on MainActor.
    ///
    /// Algorithm: deactivate all currently-active sessions, then for each active project
    /// fetch only the single most recent session and mark it active. O(activeProjects)
    /// fetches with `fetchLimit = 1`, replacing the old O(n²) in-memory scan.
    func applyActiveStatus(activeProjects: Set<String>) {
        // Step 1: deactivate all currently-active sessions
        let activeDescriptor = FetchDescriptor<SessionUsage>(
            predicate: #Predicate { $0.isActive == true }
        )
        if let currentlyActive = try? modelContext.fetch(activeDescriptor) {
            for session in currentlyActive {
                session.isActive = false
            }
        }

        // Step 2: for each running project, activate its most recent session
        for projectName in activeProjects {
            var descriptor = FetchDescriptor<SessionUsage>(
                predicate: #Predicate { $0.projectName == projectName },
                sortBy: [SortDescriptor(\.lastTime, order: .reverse)]
            )
            descriptor.fetchLimit = 1
            if let latest = try? modelContext.fetch(descriptor).first {
                latest.isActive = true
            }
        }
        try? modelContext.save()
    }

    /// Returns project names for running claude processes. Safe to call from any thread.
    /// Single lsof call with all PIDs at once to minimize overhead.
    nonisolated static func getActiveClaudeProjects() async -> Set<String> {
        // Step 1: get PIDs via ps
        let psResult = await ProcessRunner.run(
            executable: "/bin/ps",
            arguments: ["-eo", "pid,comm"]
        )
        guard let psOutput = psResult.outputString else { return [] }

        var pids: [String] = []
        for line in psOutput.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasSuffix("/claude") || trimmed.hasSuffix(" claude") {
                let parts = trimmed.split(separator: " ", maxSplits: 1)
                if let pid = parts.first { pids.append(String(pid)) }
            }
        }
        guard !pids.isEmpty else { return [] }

        // Step 2: single lsof call with all PIDs
        let lsofResult = await ProcessRunner.run(
            executable: "/usr/sbin/lsof",
            arguments: ["-a", "-d", "cwd", "-p", pids.joined(separator: ",")]
        )
        guard let output = lsofResult.outputString else { return [] }

        var projects = Set<String>()
        for line in output.components(separatedBy: "\n") {
            guard line.contains("cwd") else { continue }
            let parts = line.split(separator: " ", maxSplits: 8)
            if parts.count >= 9 {
                let path = String(parts[8])
                let name = URL(fileURLWithPath: path).lastPathComponent
                projects.insert(name)
            }
        }
        return projects
    }

    func flush() {
        if pendingSaveCount > 0 {
            try? modelContext.save()
            pendingSaveCount = 0
        }
    }

    func fetchDailyUsages(from startDate: Date, to endDate: Date) -> [DailyUsage] {
        let start = Calendar.current.startOfDay(for: startDate)
        let end = Calendar.current.startOfDay(for: endDate)
        let descriptor = FetchDescriptor<DailyUsage>(
            predicate: #Predicate { $0.date >= start && $0.date <= end },
            sortBy: [SortDescriptor(\.date)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Returns 24 hourly token totals for a given day, read from HourlyUsage rows.
    /// Replaces the view's `@Query var allHourlyUsages` which loaded the entire table.
    func fetchHourlyUsageBuckets(for date: Date) -> [Int] {
        let day = Calendar.current.startOfDay(for: date)
        let descriptor = FetchDescriptor<HourlyUsage>(
            predicate: #Predicate { $0.date == day }
        )
        guard let entries = try? modelContext.fetch(descriptor) else {
            return Array(repeating: 0, count: 24)
        }
        var buckets = Array(repeating: 0, count: 24)
        for entry in entries where entry.hour >= 0 && entry.hour < 24 {
            buckets[entry.hour] += entry.tokens
        }
        return buckets
    }

    /// Returns 24 hourly token totals for a given day, computed from SessionUsage timestamps
    func fetchHourlyTokens(for date: Date) -> [Int] {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else {
            return Array(repeating: 0, count: 24)
        }

        let descriptor = FetchDescriptor<SessionUsage>(
            predicate: #Predicate<SessionUsage> { session in
                session.startTime < dayEnd && session.lastTime >= dayStart
            }
        )
        guard let sessions = try? modelContext.fetch(descriptor), !sessions.isEmpty else {
            return Array(repeating: 0, count: 24)
        }

        var buckets = Array(repeating: 0, count: 24)
        for session in sessions {
            // Distribute tokens to the hour of startTime (simple attribution)
            let hour = cal.component(.hour, from: max(session.startTime, dayStart))
            buckets[hour] += session.totalTokens
        }
        return buckets
    }

    /// Returns token totals for the last 3 hours: [h-2, h-1, h]
    func fetchHourlyBuckets() -> [Int] {
        let cal = Calendar.current
        let now = Date()
        let currentHour = cal.component(.hour, from: now)
        let today = cal.startOfDay(for: now)

        // Build hour start/end for last 3 hours
        var buckets = [0, 0, 0]
        for i in 0..<3 {
            let hour = currentHour - 2 + i
            guard let hourStart = cal.date(bySettingHour: hour, minute: 0, second: 0, of: today),
                  let hourEnd = cal.date(bySettingHour: hour, minute: 59, second: 59, of: today) else { continue }

            let descriptor = FetchDescriptor<SessionUsage>(
                predicate: #Predicate<SessionUsage> { session in
                    session.lastTime >= hourStart && session.startTime <= hourEnd
                }
            )
            if let sessions = try? modelContext.fetch(descriptor) {
                buckets[i] = sessions.reduce(0) { $0 + $1.totalTokens }
            }
        }
        return buckets
    }
}
