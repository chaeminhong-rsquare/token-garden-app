import Foundation
import SwiftData

@MainActor
class TokenDataStore: ObservableObject {
    private let modelContainer: ModelContainer
    private let modelContext: ModelContext
    private var pendingSaveCount = 0
    private static let saveInterval = 10

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        self.modelContext = ModelContext(modelContainer)
    }

    func record(_ event: TokenEvent) {
        let day = Calendar.current.startOfDay(for: event.timestamp)

        let descriptor = FetchDescriptor<DailyUsage>(
            predicate: #Predicate { $0.date == day }
        )

        let daily: DailyUsage
        if let existing = try? modelContext.fetch(descriptor).first {
            daily = existing
        } else {
            daily = DailyUsage(date: day)
            modelContext.insert(daily)
        }

        daily.inputTokens += event.inputTokens
        daily.outputTokens += event.outputTokens
        daily.cacheCreationTokens += event.cacheCreationTokens
        daily.cacheReadTokens += event.cacheReadTokens

        if let projectName = event.projectName {
            if let existing = daily.projectBreakdowns.first(where: { $0.projectName == projectName }) {
                existing.tokens += event.totalTokens
            } else {
                let projectUsage = ProjectUsage(
                    projectName: projectName,
                    tokens: event.totalTokens,
                    model: event.model
                )
                projectUsage.dailyUsage = daily
                daily.projectBreakdowns.append(projectUsage)
            }
        }

        // Session tracking
        if let sessionId = event.sessionId {
            let sessionDescriptor = FetchDescriptor<SessionUsage>(
                predicate: #Predicate { $0.sessionId == sessionId }
            )
            if let session = try? modelContext.fetch(sessionDescriptor).first {
                session.totalTokens += event.totalTokens
                session.lastTime = event.timestamp
                session.isActive = true
            } else {
                let session = SessionUsage(
                    sessionId: sessionId,
                    projectName: event.projectName ?? "Unknown",
                    startTime: event.timestamp
                )
                session.totalTokens = event.totalTokens
                session.lastTime = event.timestamp
                modelContext.insert(session)
            }
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

    /// Refresh active status by checking running claude processes.
    /// Uses `lsof` to find active claude process working directories,
    /// then matches against recent sessions by project name.
    func refreshActiveStatus() {
        let descriptor = FetchDescriptor<SessionUsage>()
        guard let sessions = try? modelContext.fetch(descriptor) else { return }

        // Get active claude process cwds
        let activeProjects = getActiveClaudeProjects()

        // Also check file modification time as fallback
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let claudePath = "\(home)/.claude/projects"
        let fm = FileManager.default
        let recentThreshold = Date().addingTimeInterval(-300)

        for session in sessions {
            session.isActive = false

            // Check if project matches a running claude process
            if activeProjects.contains(session.projectName) {
                // Verify this is the most recent session for that project
                let projectSessions = sessions
                    .filter { $0.projectName == session.projectName }
                    .sorted { $0.lastTime > $1.lastTime }
                if projectSessions.first?.sessionId == session.sessionId {
                    session.isActive = true
                    continue
                }
            }

            // Fallback: check file modification time
            guard let enumerator = fm.enumerator(atPath: claudePath) else { continue }
            while let relativePath = enumerator.nextObject() as? String {
                guard relativePath.hasSuffix("\(session.sessionId).jsonl") else { continue }
                let fullPath = (claudePath as NSString).appendingPathComponent(relativePath)
                let attrs = try? fm.attributesOfItem(atPath: fullPath)
                let modDate = attrs?[.modificationDate] as? Date ?? .distantPast
                if modDate > recentThreshold {
                    session.isActive = true
                }
                break
            }
        }
        try? modelContext.save()
    }

    /// Returns project names (last path component of cwd) for running claude processes.
    private func getActiveClaudeProjects() -> Set<String> {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-a", "-d", "cwd", "-c", "claude"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var projects = Set<String>()
        for line in output.components(separatedBy: "\n") {
            guard line.hasPrefix("claude") else { continue }
            // lsof output: COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
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
