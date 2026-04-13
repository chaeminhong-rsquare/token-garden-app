import AppKit
import SwiftUI
import SwiftData
import SQLite3

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
    private var overviewViewModel: OverviewViewModel!

    // Session refresh via structured concurrency
    private var sessionRefreshTask: Task<Void, Never>?
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
            // Backup profiles before reset — checkpoints WAL so recently-saved
            // rows that only exist in the write-ahead log are visible.
            let backup = Self.backupProfiles(from: storeURL)

            // Preserve the old store instead of deleting it. A failed backup
            // (couldn't open DB, prepare failed, etc.) must not lead to silent
            // data loss — the previous store is renamed to a timestamped
            // sibling so users can recover manually.
            let storeDir = storeURL.deletingLastPathComponent()
            Self.archiveStoreFiles(in: storeDir, storeName: storeURL.lastPathComponent)
            try? FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
            UserDefaults.standard.removeObject(forKey: "LogWatcherOffsets")
            modelContainer = try! ModelContainer(for: schema, configurations: [config])

            // Restore profiles after reset
            Self.restoreProfiles(backup.profiles, into: modelContainer.mainContext)
        }
        dataStore = TokenDataStore(modelContainer: modelContainer)

        // Profile Manager
        profileManager = ProfileManager(modelContext: modelContainer.mainContext)
        if let activeProfile = profileManager.activeProfile {
            dataStore.activeProfileName = activeProfile.name
        }
        profileManager.prefetchAllUsageLimits()

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

        // Animation timer — tick() itself handles dirty tracking to skip redundant renders
        animationTimer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.menuBarController.tick()
            }
        }
        RunLoop.main.add(animationTimer, forMode: .common)

        // Update checker
        updateChecker = UpdateChecker()
        updateChecker.check()

        // Overview View Model — starts loading data immediately so it's
        // already in memory by the time the user clicks the menu bar.
        overviewViewModel = OverviewViewModel(modelContainer: modelContainer)
        overviewViewModel.start()

        // Popover
        popover = NSPopover()
        popover.behavior = .transient

        let popoverView = PopoverView()
            .environmentObject(menuBarController)
            .environmentObject(updateChecker)
            .environmentObject(profileManager)
            .environmentObject(dataStore)
            .environment(overviewViewModel)
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
            self?.overviewViewModel.onTokenEvent()

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
            // Backfill finished — kick a fresh snapshot so the VM sees the
            // newly persisted data.
            self?.overviewViewModel.refresh()
        }


        logWatcher.start()

        // Background session refresh loop
        startSessionRefreshLoop()

        profileManager.startTokenKeeper()
    }

    /// Run refresh once on background, apply result on main actor.
    private func triggerRefresh() {
        Task.detached(priority: .utility) { [weak self] in
            let projects = await TokenDataStore.getActiveClaudeProjects()
            await MainActor.run {
                self?.dataStore.applyActiveStatus(activeProjects: projects)
            }
        }
    }

    // MARK: - Session Refresh (structured concurrency)

    private func startSessionRefreshLoop() {
        sessionRefreshTask = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                let projects = await TokenDataStore.getActiveClaudeProjects()
                if Task.isCancelled { return }
                await MainActor.run {
                    self?.dataStore.applyActiveStatus(activeProjects: projects)
                }
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        sessionRefreshTask?.cancel()
        sessionRefreshTask = nil
        logWatcher?.stop()
    }

    // MARK: - Popover

    // MARK: - Profile Backup/Restore (survives DB reset)

    struct ProfileBackup: Codable {
        let name: String
        let email: String
        let plan: String
        let credentialsJSON: Data
        let isActive: Bool
        let monthlyLimit: Int
        let colorName: String
    }

    /// Result of a profile backup attempt.
    /// `didReadDatabase` distinguishes "DB opened and table read successfully"
    /// (empty result means no profiles) from "could not read at all" (schema
    /// mismatch, locked DB, missing file — empty result is not authoritative).
    struct ProfileBackupResult {
        let profiles: [ProfileBackup]
        let didReadDatabase: Bool
    }

    static func backupProfiles(from storeURL: URL) -> ProfileBackupResult {
        // Read profiles directly via SQLite before DB is destroyed.
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            return ProfileBackupResult(profiles: [], didReadDatabase: false)
        }

        var db: OpaquePointer?
        guard sqlite3_open(storeURL.path, &db) == SQLITE_OK else {
            return ProfileBackupResult(profiles: [], didReadDatabase: false)
        }
        defer { sqlite3_close(db) }

        // Fold any WAL rows into the main DB before reading. If the previous
        // app instance crashed before a checkpoint (e.g., right after saving
        // a profile), those rows only exist in the WAL and a naive
        // `sqlite3_open` + SELECT would miss them, causing the subsequent
        // reset path to silently destroy unbacked-up profiles.
        sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE)", nil, nil, nil)

        var stmt: OpaquePointer?
        let sql = "SELECT ZNAME, ZEMAIL, ZPLAN, ZCREDENTIALSJSON, ZISACTIVE, ZMONTHLYLIMIT, ZCOLORNAME FROM ZPROFILE"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return ProfileBackupResult(profiles: [], didReadDatabase: false)
        }
        defer { sqlite3_finalize(stmt) }

        var backups: [ProfileBackup] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let name = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
            let email = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let plan = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
            let credLen = sqlite3_column_bytes(stmt, 3)
            let credData: Data
            if credLen > 0, let ptr = sqlite3_column_blob(stmt, 3) {
                credData = Data(bytes: ptr, count: Int(credLen))
            } else {
                credData = Data()
            }
            let isActive = sqlite3_column_int(stmt, 4) != 0
            let monthlyLimit = Int(sqlite3_column_int(stmt, 5))
            let colorName = sqlite3_column_text(stmt, 6).map { String(cString: $0) } ?? "blue"

            guard !name.isEmpty else { continue }
            backups.append(ProfileBackup(
                name: name, email: email, plan: plan,
                credentialsJSON: credData, isActive: isActive,
                monthlyLimit: monthlyLimit, colorName: colorName
            ))
        }
        return ProfileBackupResult(profiles: backups, didReadDatabase: true)
    }

    /// Renames the existing store files to a timestamped archive next to the
    /// store directory. This preserves data on schema-migration failures so a
    /// user or developer can recover manually, instead of silently deleting it.
    static func archiveStoreFiles(in storeDir: URL, storeName: String) {
        let fm = FileManager.default
        let suffixes = ["", "-shm", "-wal"]
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        for suffix in suffixes {
            let src = storeDir.appendingPathComponent(storeName + suffix)
            guard fm.fileExists(atPath: src.path) else { continue }
            let dst = storeDir.appendingPathComponent("\(storeName).corrupted-\(timestamp)\(suffix)")
            try? fm.moveItem(at: src, to: dst)
        }
    }

    private static func restoreProfiles(_ backups: [ProfileBackup], into context: ModelContext) {
        for b in backups {
            let profile = Profile(name: b.name, email: b.email, plan: b.plan, credentialsJSON: b.credentialsJSON)
            profile.isActive = b.isActive
            profile.monthlyLimit = b.monthlyLimit
            profile.colorName = b.colorName
            context.insert(profile)
        }
        try? context.save()
    }

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
