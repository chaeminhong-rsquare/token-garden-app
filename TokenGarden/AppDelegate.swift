import AppKit
import SwiftUI
import SwiftData

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var menuBarController: MenuBarController!
    private var logWatcher: LogWatcher!
    private var dataStore: TokenDataStore!
    private var modelContainer: ModelContainer!
    private var animationTimer: Timer!
    private var updateChecker: UpdateChecker!
    private var profileManager: ProfileManager!

    // Session refresh: background thread writes, main thread reads
    private nonisolated(unsafe) let refreshLock = NSLock()
    private nonisolated(unsafe) var pendingActiveProjects: Set<String>?
    private var lastBalancedSessionId: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Single instance guard
        let bundleId = Bundle.main.bundleIdentifier ?? "com.tokengarden"
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
        if running.count > 1 {
            NSApp.terminate(nil)
            return
        }

        NSApp.setActivationPolicy(.accessory)

        // SwiftData
        let schema = Schema([DailyUsage.self, ProjectUsage.self, SessionUsage.self, HourlyUsage.self, Profile.self, ProfileTokenUsage.self])
        let storeURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TokenGarden", isDirectory: true)
            .appendingPathComponent("TokenGarden.store")
        try? FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let config = ModelConfiguration("TokenGarden", schema: schema, url: storeURL)
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            // New model added — reset store and backfill offsets to rebuild from logs
            let storeDir = storeURL.deletingLastPathComponent()
            try? FileManager.default.removeItem(at: storeDir)
            try? FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
            UserDefaults.standard.removeObject(forKey: "LogWatcherOffsets")
            modelContainer = try! ModelContainer(for: schema, configurations: [config])
        }
        dataStore = TokenDataStore(modelContainer: modelContainer)

        // Profile Manager
        profileManager = ProfileManager(modelContext: modelContainer.mainContext)
        if let activeProfile = profileManager.activeProfile {
            dataStore.activeProfileName = activeProfile.name
        }

        // Status Item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = AnimationFrames.idleImage()
            button.action = #selector(togglePopover)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // MenuBar Controller
        menuBarController = MenuBarController(statusItem: statusItem, initialTodayTokens: 0, initialHourlyBuckets: [0, 0, 0])

        // Animation timer — also checks for pending session refresh
        animationTimer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.menuBarController.tick()
                self?.applyPendingRefreshIfNeeded()
            }
        }
        RunLoop.main.add(animationTimer, forMode: .common)

        // Update checker
        updateChecker = UpdateChecker()
        updateChecker.check()

        // Popover
        popover = NSPopover()
        popover.behavior = .transient

        let popoverView = PopoverView()
            .environmentObject(menuBarController)
            .environmentObject(updateChecker)
            .environmentObject(profileManager)
            .modelContainer(modelContainer)
        let hostingController = NSHostingController(rootView: popoverView)
        hostingController.sizingOptions = .preferredContentSize
        popover.contentViewController = hostingController

        // Log Parser + Watcher
        let parser = ClaudeCodeLogParser()
        logWatcher = LogWatcher(watchPaths: parser.watchPaths) { [weak self] line in
            guard let event = parser.parse(logLine: line) else { return }
            self?.dataStore.record(event)
            self?.menuBarController.onTokenEvent(event)

            // Auto-balance only when session changes
            if let sessionId = event.sessionId,
               sessionId != self?.lastBalancedSessionId,
               UserDefaults.standard.bool(forKey: "autoBalancingEnabled") {
                self?.lastBalancedSessionId = sessionId
                self?.profileManager.balanceIfNeeded()
                if let name = self?.profileManager.activeProfile?.name {
                    self?.dataStore.activeProfileName = name
                }
            }
        }

        // Backfill on background thread — UI stays responsive
        logWatcher.backfill(parser: parser) { [weak self] event in
            self?.dataStore.record(event)
            self?.menuBarController.onTokenEvent(event)
        } completion: { [weak self] in
            // Trigger refresh right after backfill so dead sessions get cleared
            self?.dataStore.flush()
            self?.triggerRefresh()
            let todayTokens = self?.dataStore.fetchDailyUsages(
                from: Calendar.current.startOfDay(for: Date()),
                to: Date()
            ).first?.totalTokens ?? 0
            let hourlyBuckets = self?.dataStore.fetchHourlyBuckets() ?? [0, 0, 0]
            self?.menuBarController.reloadData(todayTokens: todayTokens, hourlyBuckets: hourlyBuckets)
        }


        logWatcher.start()

        // Background session refresh loop
        startSessionRefreshLoop()

        profileManager.startTokenKeeper()
    }

    /// Run refresh immediately on background, result applied on next timer tick
    private func triggerRefresh() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let projects = TokenDataStore.getActiveClaudeProjects()
            self?.refreshLock.lock()
            self?.pendingActiveProjects = projects
            self?.refreshLock.unlock()
        }
    }

    // MARK: - Session Refresh (background → main via polling)

    private func startSessionRefreshLoop() {
        Thread.detachNewThread { [weak self] in

            while true {
                let projects = TokenDataStore.getActiveClaudeProjects()

                self?.refreshLock.lock()
                self?.pendingActiveProjects = projects
                self?.refreshLock.unlock()
                Thread.sleep(forTimeInterval: 30)
            }
        }
    }

    private func applyPendingRefreshIfNeeded() {
        refreshLock.lock()
        let projects = pendingActiveProjects
        pendingActiveProjects = nil
        refreshLock.unlock()

        if let projects {

            dataStore.applyActiveStatus(activeProjects: projects)
        }
    }

    // MARK: - Popover

    @objc func togglePopover() {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "Quit Token Garden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.statusItem.menu = nil
            }
            return
        }

        statusItem.menu = nil
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}
