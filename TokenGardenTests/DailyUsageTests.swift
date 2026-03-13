import Testing
import Foundation
import SwiftData
@testable import TokenGarden

@Test func dailyUsageCreation() throws {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: DailyUsage.self, ProjectUsage.self, configurations: config)
    let context = ModelContext(container)

    let today = Calendar.current.startOfDay(for: Date())
    let usage = DailyUsage(date: today)
    usage.inputTokens = 1000
    usage.outputTokens = 500
    usage.cacheCreationTokens = 200
    usage.cacheReadTokens = 50
    context.insert(usage)
    try context.save()

    let descriptor = FetchDescriptor<DailyUsage>()
    let results = try context.fetch(descriptor)
    #expect(results.count == 1)
    #expect(results[0].totalTokens == 1500)
}

@Test func dailyUsageWithProjectBreakdown() throws {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: DailyUsage.self, ProjectUsage.self, configurations: config)
    let context = ModelContext(container)

    let today = Calendar.current.startOfDay(for: Date())
    let daily = DailyUsage(date: today)
    daily.inputTokens = 1000
    daily.outputTokens = 500

    let project = ProjectUsage(projectName: "token-garden", tokens: 800, model: "claude-opus-4-6")
    project.dailyUsage = daily
    daily.projectBreakdowns.append(project)

    context.insert(daily)
    try context.save()

    let descriptor = FetchDescriptor<DailyUsage>()
    let results = try context.fetch(descriptor)
    #expect(results[0].projectBreakdowns.count == 1)
    #expect(results[0].projectBreakdowns[0].projectName == "token-garden")
}
