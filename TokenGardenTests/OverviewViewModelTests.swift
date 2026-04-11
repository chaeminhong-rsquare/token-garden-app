import Testing
import SwiftData
import Foundation
@testable import TokenGarden

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

@Test @MainActor func vm_initialState_isLoading() async throws {
    let container = try makeContainer()
    let vm = OverviewViewModel(modelContainer: container)

    // Before start(), the VM must be in the "loading" state so the view
    // shows a skeleton rather than flashing empty content.
    #expect(vm.isInitialLoading == true)
    #expect(vm.snapshot.hasAnyData == false)
    #expect(vm.selectedDate == nil)
}

@Test @MainActor func vm_start_flipsLoadingFalseAfterLoad() async throws {
    let container = try makeContainer()
    let vm = OverviewViewModel(modelContainer: container)

    vm.start()
    await vm.awaitPendingTasks()

    #expect(vm.isInitialLoading == false)
    #expect(vm.snapshot.hasAnyData == false)  // empty DB
}

@Test @MainActor func vm_start_loadsSnapshotFromDB() async throws {
    let container = try makeContainer()
    let context = ModelContext(container)

    let today = Calendar.current.startOfDay(for: Date())
    let daily = DailyUsage(date: today)
    daily.inputTokens = 300
    daily.outputTokens = 200
    context.insert(daily)
    try context.save()

    let vm = OverviewViewModel(modelContainer: container)
    vm.start()
    await vm.awaitPendingTasks()

    #expect(vm.isInitialLoading == false)
    #expect(vm.snapshot.hasAnyData == true)
    #expect(vm.snapshot.todayTokens == 500)
}

@Test @MainActor func vm_selectedDate_triggersProjectLoad() async throws {
    let container = try makeContainer()
    let context = ModelContext(container)

    let today = Calendar.current.startOfDay(for: Date())
    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!

    let daily = DailyUsage(date: yesterday)
    context.insert(daily)
    let project = ProjectUsage(projectName: "historical-app", tokens: 300)
    project.dailyUsage = daily
    daily.projectBreakdowns.append(project)
    context.insert(project)
    try context.save()

    let vm = OverviewViewModel(modelContainer: container)
    vm.start()
    await vm.awaitPendingTasks()

    // No selection yet → selectedDayProjects should be nil
    #expect(vm.selectedDayProjects == nil)

    // Selecting yesterday should trigger a background fetch
    vm.selectedDate = yesterday
    await vm.awaitPendingTasks()

    #expect(vm.selectedDayProjects != nil)
    #expect(vm.selectedDayProjects?.count == 1)
    #expect(vm.selectedDayProjects?.first?.name == "historical-app")
}

@Test @MainActor func vm_selectedDate_nilResetsSelection() async throws {
    let container = try makeContainer()
    let vm = OverviewViewModel(modelContainer: container)

    vm.start()
    await vm.awaitPendingTasks()

    vm.selectedDate = Date()
    await vm.awaitPendingTasks()

    // Setting to nil must clear selectedDayProjects synchronously.
    vm.selectedDate = nil
    #expect(vm.selectedDayProjects == nil)
}
