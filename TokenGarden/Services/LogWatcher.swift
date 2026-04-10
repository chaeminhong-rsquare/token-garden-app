import Foundation

@MainActor
class LogWatcher {
    private let watchPaths: [String]
    private let onNewLine: @MainActor (String) -> Void
    private var stream: FSEventStreamRef?
    private var fileOffsets: [String: Int] = [:]
    private let offsetsKey = "LogWatcherOffsets"
    private let debouncedSave: DebouncedPersistence

    init(watchPaths: [String], onNewLine: @escaping @MainActor (String) -> Void) {
        self.watchPaths = watchPaths
        self.onNewLine = onNewLine
        self.debouncedSave = DebouncedPersistence(key: "LogWatcherOffsets", delay: 2.0)
        loadOffsets()
    }

    func start() {
        let pathsToWatch = watchPaths as CFArray
        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        guard let stream = FSEventStreamCreate(
            nil,
            LogWatcher.eventCallback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        ) else { return }

        self.stream = stream
        FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        FSEventStreamStart(stream)
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        debouncedSave.flushNow()
    }

    nonisolated private static let eventCallback: FSEventStreamCallback = { _, info, numEvents, eventPaths, _, _ in
        guard let info else { return }
        let watcher = Unmanaged<LogWatcher>.fromOpaque(info).takeUnretainedValue()
        guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }

        let filteredPaths = paths.filter { path in
            path.hasSuffix(".jsonl") && !URL(fileURLWithPath: path).lastPathComponent.contains("compact")
        }

        Task { @MainActor in
            for path in filteredPaths {
                watcher.processFile(at: path)
            }
        }
    }

    private func processFile(at path: String) {
        guard FileManager.default.fileExists(atPath: path),
              let handle = FileHandle(forReadingAtPath: path) else { return }
        defer { handle.closeFile() }

        let fileSize = Int(handle.seekToEndOfFile())
        let offset = fileOffsets[path] ?? 0

        if offset > fileSize {
            fileOffsets[path] = 0
            handle.seek(toFileOffset: 0)
        } else {
            handle.seek(toFileOffset: UInt64(offset))
        }

        let data = handle.readDataToEndOfFile()
        fileOffsets[path] = Int(handle.offsetInFile)
        debouncedSave.schedule(fileOffsets)

        guard let content = String(data: data, encoding: .utf8) else { return }
        let lines = content.components(separatedBy: .newlines)
        for line in lines where !line.isEmpty {
            onNewLine(line)
        }
    }

    /// Backfill on background thread. Reads files and parses lines off-main,
    /// then delivers parsed TokenEvents to the callback in batches.
    ///
    /// Scans `<watchPath>/projects/` first (Claude Code's actual log location).
    /// Falls back to full recursive enumeration if that path doesn't exist.
    func backfill(parser: ClaudeCodeLogParser, onEvent: @escaping @MainActor (TokenEvent) -> Void, completion: @escaping @MainActor () -> Void = {}) {
        let currentOffsets = fileOffsets
        let paths = watchPaths

        DispatchQueue.global(qos: .utility).async { [weak self] in
            var events: [TokenEvent] = []
            var newOffsets: [String: Int] = [:]

            for watchPath in paths {
                // Prefer targeted projects/ subdirectory
                let projectsPath = (watchPath as NSString).appendingPathComponent("projects")
                let rootPath = FileManager.default.fileExists(atPath: projectsPath) ? projectsPath : watchPath

                guard let enumerator = FileManager.default.enumerator(atPath: rootPath) else { continue }
                while let relativePath = enumerator.nextObject() as? String {
                    guard relativePath.hasSuffix(".jsonl"),
                          !URL(fileURLWithPath: relativePath).lastPathComponent.contains("compact") else { continue }
                    let fullPath = (rootPath as NSString).appendingPathComponent(relativePath)
                    guard currentOffsets[fullPath] == nil else { continue }

                    guard let handle = FileHandle(forReadingAtPath: fullPath) else { continue }
                    let data = handle.readDataToEndOfFile()
                    newOffsets[fullPath] = Int(handle.offsetInFile)
                    handle.closeFile()

                    guard let content = String(data: data, encoding: .utf8) else { continue }
                    for line in content.components(separatedBy: .newlines) where !line.isEmpty {
                        if let event = parser.parse(logLine: line) {
                            events.append(event)
                        }
                    }
                }
            }

            // Deliver results to main in one batch
            DispatchQueue.main.async {
                guard let self else { return }
                MainActor.assumeIsolated {
                    for (path, offset) in newOffsets {
                        self.fileOffsets[path] = offset
                    }
                    self.debouncedSave.schedule(self.fileOffsets)
                    for event in events {
                        onEvent(event)
                    }
                    completion()
                }
            }
        }
    }

    private func loadOffsets() {
        fileOffsets = UserDefaults.standard.dictionary(forKey: offsetsKey) as? [String: Int] ?? [:]
    }
}
