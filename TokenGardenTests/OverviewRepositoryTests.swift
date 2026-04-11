import Testing
import SwiftData
import Foundation
@testable import TokenGarden

// MARK: - Helpers

@MainActor
private func makeContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(
        for: DailyUsage.self,
        ProjectUsage.self,
        SessionUsage.self,
        HourlyUsage.self,
        configurations: config
    )
}

// MARK: - loadSnapshot

@Test @MainActor func loadSnapshot_emptyDB_returnsEmptySnapshot() async throws {
    let container = try makeContainer()
    let repository = OverviewRepository(modelContainer: container)

    let snapshot = await repository.loadSnapshot()

    #expect(snapshot.hasAnyData == false)
    #expect(snapshot.todayTokens == 0)
    #expect(snapshot.weekTokens == 0)
    #expect(snapshot.monthTokens == 0)
    #expect(snapshot.heatmapData.isEmpty)
    #expect(snapshot.todayProjects.isEmpty)
    #expect(snapshot.activeSessions.isEmpty)
    #expect(snapshot.hourlyTokens.count == 24)
    #expect(snapshot.hourlyTokens.allSatisfy { $0 == 0 })
}

@Test @MainActor func loadSnapshot_aggregatesTodayTokens() async throws {
    let container = try makeContainer()
    let context = ModelContext(container)

    let today = Calendar.current.startOfDay(for: Date())
    let todayUsage = DailyUsage(date: today)
    todayUsage.inputTokens = 100
    todayUsage.outputTokens = 50
    context.insert(todayUsage)

    // A very old entry — outside week and month windows. Proves the
    // aggregation windows filter correctly regardless of today's date.
    let yearAgo = Calendar.current.date(byAdding: .day, value: -365, to: today)!
    let oldUsage = DailyUsage(date: yearAgo)
    oldUsage.inputTokens = 999
    oldUsage.outputTokens = 999
    context.insert(oldUsage)

    try context.save()

    let repository = OverviewRepository(modelContainer: container)
    let snapshot = await repository.loadSnapshot()

    #expect(snapshot.todayTokens == 150)
    #expect(snapshot.weekTokens == 150)   // yearAgo excluded
    #expect(snapshot.monthTokens == 150)  // yearAgo excluded
    #expect(snapshot.hasAnyData == true)
    #expect(snapshot.heatmapData.count == 2)
}

@Test @MainActor func loadSnapshot_aggregatesProjectBreakdownsForToday() async throws {
    let container = try makeContainer()
    let context = ModelContext(container)

    let today = Calendar.current.startOfDay(for: Date())
    let daily = DailyUsage(date: today)
    daily.inputTokens = 150
    daily.outputTokens = 0
    context.insert(daily)

    let projectA = ProjectUsage(projectName: "app-a", tokens: 80)
    projectA.dailyUsage = daily
    daily.projectBreakdowns.append(projectA)
    context.insert(projectA)

    let projectB = ProjectUsage(projectName: "app-b", tokens: 70)
    projectB.dailyUsage = daily
    daily.projectBreakdowns.append(projectB)
    context.insert(projectB)

    try context.save()

    let repository = OverviewRepository(modelContainer: container)
    let snapshot = await repository.loadSnapshot()

    #expect(snapshot.todayProjects.count == 2)
    let appA = snapshot.todayProjects.first { $0.name == "app-a" }
    let appB = snapshot.todayProjects.first { $0.name == "app-b" }
    #expect(appA?.tokens == 80)
    #expect(appB?.tokens == 70)
}

@Test @MainActor func loadSnapshot_excludesInactiveSessions() async throws {
    let container = try makeContainer()
    let context = ModelContext(container)

    let active = SessionUsage(sessionId: "s1", projectName: "proj-a", startTime: Date())
    active.isActive = true
    active.totalTokens = 500
    context.insert(active)

    let dead = SessionUsage(sessionId: "s2", projectName: "proj-b", startTime: Date())
    dead.isActive = false
    dead.totalTokens = 300
    context.insert(dead)

    try context.save()

    let repository = OverviewRepository(modelContainer: container)
    let snapshot = await repository.loadSnapshot()

    #expect(snapshot.activeSessions.count == 1)
    #expect(snapshot.activeSessions.first?.sessionId == "s1")
    #expect(snapshot.activeSessions.first?.totalTokens == 500)
}

// MARK: - loadHourlyTokens

@Test @MainActor func loadHourlyTokens_bucketsHoursCorrectly() async throws {
    let container = try makeContainer()
    let context = ModelContext(container)

    let today = Calendar.current.startOfDay(for: Date())
    context.insert(HourlyUsage(date: today, hour: 0, tokens: 10))
    context.insert(HourlyUsage(date: today, hour: 12, tokens: 500))
    context.insert(HourlyUsage(date: today, hour: 23, tokens: 100))

    try context.save()

    let repository = OverviewRepository(modelContainer: container)
    let hourly = await repository.loadHourlyTokens(for: today)

    #expect(hourly.count == 24)
    #expect(hourly[0] == 10)
    #expect(hourly[12] == 500)
    #expect(hourly[23] == 100)
    // Boundary: hours with no entry are 0, not nil.
    #expect(hourly[1] == 0)
    #expect(hourly[22] == 0)
}

@Test @MainActor func loadHourlyTokens_ignoresOtherDates() async throws {
    let container = try makeContainer()
    let context = ModelContext(container)

    let today = Calendar.current.startOfDay(for: Date())
    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!

    context.insert(HourlyUsage(date: today, hour: 5, tokens: 100))
    context.insert(HourlyUsage(date: yesterday, hour: 5, tokens: 999))

    try context.save()

    let repository = OverviewRepository(modelContainer: container)
    let hourly = await repository.loadHourlyTokens(for: today)

    #expect(hourly[5] == 100)  // yesterday's 999 must not leak into today
}

// MARK: - loadProjects

@Test @MainActor func loadProjects_returnsOnlyForRequestedDate() async throws {
    let container = try makeContainer()
    let context = ModelContext(container)

    let today = Calendar.current.startOfDay(for: Date())
    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!

    let todayDaily = DailyUsage(date: today)
    context.insert(todayDaily)
    let todayProject = ProjectUsage(projectName: "todays-app", tokens: 100)
    todayProject.dailyUsage = todayDaily
    todayDaily.projectBreakdowns.append(todayProject)
    context.insert(todayProject)

    let yesterdayDaily = DailyUsage(date: yesterday)
    context.insert(yesterdayDaily)
    let yesterdayProject = ProjectUsage(projectName: "yesterdays-app", tokens: 300)
    yesterdayProject.dailyUsage = yesterdayDaily
    yesterdayDaily.projectBreakdowns.append(yesterdayProject)
    context.insert(yesterdayProject)

    try context.save()

    let repository = OverviewRepository(modelContainer: container)
    let projects = await repository.loadProjects(for: yesterday)

    #expect(projects.count == 1)
    #expect(projects.first?.name == "yesterdays-app")
    #expect(projects.first?.tokens == 300)
}
