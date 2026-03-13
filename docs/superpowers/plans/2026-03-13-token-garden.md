# Token Garden Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** GitHub 잔디 스타일로 AI 토큰 사용량을 시각화하는 macOS 네이티브 메뉴바 앱 구현

**Architecture:** 단일 SwiftUI 메뉴바 앱. FSEvents로 Claude Code 로그를 실시간 감시하고, TokenLogParser 프로토콜로 파서를 추상화. SwiftData로 일별 사용량을 로컬 저장하여 잔디 히트맵으로 시각화.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, FSEvents, macOS 14+

**Spec:** `docs/superpowers/specs/2026-03-13-token-garden-design.md`

---

## File Structure

```
TokenGarden/
├── TokenGardenApp.swift              # App entry point, NSApplicationDelegateAdaptor
├── AppDelegate.swift                 # NSStatusItem 생성, 팝오버 관리
├── Info.plist                        # LSUIElement=YES
├── Assets.xcassets/                  # 앱 아이콘, 식물 애니메이션 프레임
│   └── AppIcon.appiconset/
├── Models/
│   ├── DailyUsage.swift              # SwiftData 모델: 일별 토큰 사용량
│   ├── ProjectUsage.swift            # SwiftData 모델: 프로젝트별 사용량
│   └── TokenEvent.swift              # 파서 출력 구조체
├── Parsers/
│   ├── TokenLogParser.swift          # 파서 프로토콜 정의
│   └── ClaudeCodeLogParser.swift     # Claude Code .jsonl 파서
├── Services/
│   ├── LogWatcher.swift              # FSEvents 기반 파일 변경 감시
│   └── TokenDataStore.swift          # SwiftData CRUD, 집계 로직
├── Views/
│   ├── PopoverView.swift             # 메인 팝오버 컨테이너
│   ├── HeatmapView.swift             # 잔디 히트맵 그리드
│   ├── StatsView.swift               # 요약 통계 미니 위젯
│   ├── ProjectListView.swift         # 프로젝트별 사용량 목록
│   ├── EmptyStateView.swift          # 빈 상태 / 에러 상태 뷰
│   └── SettingsView.swift            # 설정 뷰
├── MenuBar/
│   ├── MenuBarController.swift       # 메뉴바 아이콘, 애니메이션 관리
│   └── AnimationFrames.swift         # 식물 성장 프레임 정의
└── Utilities/
    └── NumberFormatter+Tokens.swift  # 토큰 수 약식 포맷 (23.4K, 1.2M)

TokenGardenTests/
├── ClaudeCodeLogParserTests.swift    # 파서 유닛 테스트
├── TokenDataStoreTests.swift         # 데이터 저장/집계 테스트
├── LogWatcherTests.swift             # 파일 감시 테스트
└── HeatmapViewTests.swift            # 히트맵 색상 로직 테스트
```

---

## Chunk 1: Project Setup & Data Models

### Task 1: Xcode 프로젝트 생성

**Files:**
- Create: `TokenGarden.xcodeproj` (Xcode가 생성)
- Create: `TokenGarden/TokenGardenApp.swift`
- Create: `TokenGarden/Info.plist`

- [ ] **Step 1: Xcode 프로젝트 생성**

> **중요:** SPM이 아닌 Xcode 프로젝트(`.xcodeproj`)를 사용해야 합니다.
> SPM 실행 타겟은 Info.plist를 번들에 포함하지 않아 LSUIElement가 무시됩니다.
> SwiftData, Asset Catalog, Info.plist이 필요한 메뉴바 앱에는 Xcode 프로젝트가 적합합니다.

```bash
cd /Users/hongchaemin/Company/private/projects/token-garden-app
# Xcode에서 File > New > Project > macOS > App 으로 생성
# Product Name: TokenGarden
# Organization Identifier: com.tokengarden
# Interface: SwiftUI
# Language: Swift
# Storage: SwiftData
# Include Tests: Yes
# Location: /Users/hongchaemin/Company/private/projects/token-garden-app/
```

또는 CLI로 프로젝트를 생성할 수 없으므로, 빈 디렉토리 구조를 만들고
Xcode에서 프로젝트를 생성합니다:

```bash
mkdir -p TokenGarden/Models TokenGarden/Parsers TokenGarden/Services TokenGarden/Views TokenGarden/MenuBar TokenGarden/Utilities
mkdir -p TokenGardenTests
```

- [ ] **Step 2: App entry point 생성**

`TokenGarden/TokenGardenApp.swift`:

```swift
import SwiftUI

@main
struct TokenGardenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
```

`TokenGarden/AppDelegate.swift`:

```swift
import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "leaf.fill", accessibilityDescription: "Token Garden")
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 400)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PopoverView())
    }

    @objc func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}
```

`TokenGarden/Views/PopoverView.swift` (placeholder):

```swift
import SwiftUI

struct PopoverView: View {
    var body: some View {
        Text("Token Garden")
            .frame(width: 320, height: 400)
    }
}
```

- [ ] **Step 3: Info.plist에 LSUIElement 설정**

`TokenGarden/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 4: 빌드 확인**

```bash
swift build
```

Expected: 빌드 성공, 경고 없음

- [ ] **Step 5: 커밋**

```bash
git init
git add Package.swift TokenGarden/ TokenGardenTests/
git commit -m "chore: scaffold TokenGarden macOS menu bar app with SPM"
```

---

### Task 2: TokenEvent 구조체

**Files:**
- Create: `TokenGarden/Models/TokenEvent.swift`
- Create: `TokenGardenTests/TokenEventTests.swift`

- [ ] **Step 1: 테스트 작성**

`TokenGardenTests/TokenEventTests.swift`:

```swift
import Testing
@testable import TokenGarden

@Test func tokenEventTotalTokens() {
    let event = TokenEvent(
        timestamp: Date(),
        inputTokens: 100,
        outputTokens: 50,
        cacheCreationTokens: 200,
        cacheReadTokens: 30,
        model: "claude-opus-4-6",
        projectName: "my-project",
        source: "claude-code"
    )
    #expect(event.totalTokens == 150)  // input + output only
}
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
swift test --filter TokenEventTests
```

Expected: FAIL — `TokenEvent` not found

- [ ] **Step 3: TokenEvent 구현**

`TokenGarden/Models/TokenEvent.swift`:

```swift
import Foundation

struct TokenEvent: Sendable {
    let timestamp: Date
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    let model: String?
    let projectName: String?
    let source: String

    var totalTokens: Int {
        inputTokens + outputTokens
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

```bash
swift test --filter TokenEventTests
```

Expected: PASS

- [ ] **Step 5: 커밋**

```bash
git add TokenGarden/Models/TokenEvent.swift TokenGardenTests/TokenEventTests.swift
git commit -m "feat: add TokenEvent model with total token calculation"
```

---

### Task 3: SwiftData 모델 (DailyUsage, ProjectUsage)

**Files:**
- Create: `TokenGarden/Models/DailyUsage.swift`
- Create: `TokenGarden/Models/ProjectUsage.swift`
- Create: `TokenGardenTests/DailyUsageTests.swift`

- [ ] **Step 1: 테스트 작성**

`TokenGardenTests/DailyUsageTests.swift`:

```swift
import Testing
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
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
swift test --filter DailyUsageTests
```

Expected: FAIL

- [ ] **Step 3: DailyUsage 구현**

`TokenGarden/Models/DailyUsage.swift`:

```swift
import Foundation
import SwiftData

@Model
class DailyUsage {
    @Attribute(.unique) var date: Date
    var inputTokens: Int
    var outputTokens: Int
    var cacheCreationTokens: Int
    var cacheReadTokens: Int
    @Relationship(deleteRule: .cascade, inverse: \ProjectUsage.dailyUsage)
    var projectBreakdowns: [ProjectUsage]

    var totalTokens: Int {
        inputTokens + outputTokens
    }

    init(date: Date) {
        self.date = date
        self.inputTokens = 0
        self.outputTokens = 0
        self.cacheCreationTokens = 0
        self.cacheReadTokens = 0
        self.projectBreakdowns = []
    }
}
```

`TokenGarden/Models/ProjectUsage.swift`:

```swift
import Foundation
import SwiftData

@Model
class ProjectUsage {
    var projectName: String
    var tokens: Int
    var model: String?
    var dailyUsage: DailyUsage?

    init(projectName: String, tokens: Int, model: String? = nil) {
        self.projectName = projectName
        self.tokens = tokens
        self.model = model
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

```bash
swift test --filter DailyUsageTests
```

Expected: PASS

- [ ] **Step 5: 커밋**

```bash
git add TokenGarden/Models/DailyUsage.swift TokenGarden/Models/ProjectUsage.swift TokenGardenTests/DailyUsageTests.swift
git commit -m "feat: add SwiftData models for DailyUsage and ProjectUsage"
```

---

## Chunk 2: Log Parsing

### Task 4: TokenLogParser 프로토콜

**Files:**
- Create: `TokenGarden/Parsers/TokenLogParser.swift`

- [ ] **Step 1: 프로토콜 정의**

`TokenGarden/Parsers/TokenLogParser.swift`:

```swift
import Foundation

protocol TokenLogParser: Sendable {
    var name: String { get }
    var watchPaths: [String] { get }
    func parse(logLine: String) -> TokenEvent?
}
```

- [ ] **Step 2: 빌드 확인**

```bash
swift build
```

Expected: 성공

- [ ] **Step 3: 커밋**

```bash
git add TokenGarden/Parsers/TokenLogParser.swift
git commit -m "feat: add TokenLogParser protocol"
```

---

### Task 5: ClaudeCodeLogParser 구현

**Files:**
- Create: `TokenGarden/Parsers/ClaudeCodeLogParser.swift`
- Create: `TokenGardenTests/ClaudeCodeLogParserTests.swift`

실제 Claude Code 로그 구조 (`.jsonl` 한 줄):
```json
{
  "type": "assistant",
  "message": {
    "model": "claude-opus-4-6",
    "usage": {
      "input_tokens": 3,
      "output_tokens": 9,
      "cache_creation_input_tokens": 25283,
      "cache_read_input_tokens": 0
    }
  },
  "timestamp": "2026-03-13T05:23:31.807Z",
  "cwd": "/Users/hongchaemin/Company/private/projects/token-garden-app"
}
```

- [ ] **Step 1: 테스트 작성**

`TokenGardenTests/ClaudeCodeLogParserTests.swift`:

```swift
import Testing
@testable import TokenGarden

@Test func parseAssistantLine() {
    let parser = ClaudeCodeLogParser()
    let line = """
    {"type":"assistant","message":{"model":"claude-opus-4-6","id":"msg_1","type":"message","role":"assistant","content":[],"stop_reason":"end_turn","stop_sequence":null,"usage":{"input_tokens":100,"output_tokens":50,"cache_creation_input_tokens":200,"cache_read_input_tokens":30}},"timestamp":"2026-03-13T05:23:31.807Z","cwd":"/Users/test/projects/my-app","sessionId":"abc-123","uuid":"uuid-1"}
    """
    let event = parser.parse(logLine: line)
    #expect(event != nil)
    #expect(event!.inputTokens == 100)
    #expect(event!.outputTokens == 50)
    #expect(event!.cacheCreationTokens == 200)
    #expect(event!.cacheReadTokens == 30)
    #expect(event!.model == "claude-opus-4-6")
    #expect(event!.projectName == "my-app")
    #expect(event!.source == "claude-code")
    #expect(event!.totalTokens == 150)
}

@Test func skipNonAssistantLine() {
    let parser = ClaudeCodeLogParser()
    let line = """
    {"type":"user","message":{"role":"user","content":[{"type":"text","text":"hello"}]},"timestamp":"2026-03-13T05:00:00.000Z","cwd":"/Users/test/projects/my-app"}
    """
    let event = parser.parse(logLine: line)
    #expect(event == nil)
}

@Test func skipProgressLine() {
    let parser = ClaudeCodeLogParser()
    let line = """
    {"type":"progress","data":{"type":"hook_progress"},"timestamp":"2026-03-13T05:00:00.000Z","cwd":"/Users/test/projects/my-app"}
    """
    let event = parser.parse(logLine: line)
    #expect(event == nil)
}

@Test func projectNameFromCwd() {
    let parser = ClaudeCodeLogParser()
    let line = """
    {"type":"assistant","message":{"model":"claude-sonnet-4-20250514","id":"msg_1","type":"message","role":"assistant","content":[],"stop_reason":"end_turn","stop_sequence":null,"usage":{"input_tokens":10,"output_tokens":5,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"timestamp":"2026-03-13T05:00:00.000Z","cwd":"/Users/someone/Company/private/projects/deep/nested/project-name","sessionId":"s1","uuid":"u1"}
    """
    let event = parser.parse(logLine: line)
    #expect(event?.projectName == "project-name")
}

@Test func watchPathsIncludeClaudeProjects() {
    let parser = ClaudeCodeLogParser()
    #expect(parser.watchPaths.first!.hasSuffix(".claude/projects"))
}
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
swift test --filter ClaudeCodeLogParserTests
```

Expected: FAIL — `ClaudeCodeLogParser` not found

- [ ] **Step 3: ClaudeCodeLogParser 구현**

`TokenGarden/Parsers/ClaudeCodeLogParser.swift`:

```swift
import Foundation

struct ClaudeCodeLogParser: TokenLogParser {
    let name = "claude-code"

    var watchPaths: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/.claude/projects"]
    }

    func parse(logLine: String) -> TokenEvent? {
        guard let data = logLine.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String,
              type == "assistant",
              let message = json["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any],
              let inputTokens = usage["input_tokens"] as? Int,
              let outputTokens = usage["output_tokens"] as? Int,
              let timestampStr = json["timestamp"] as? String
        else {
            return nil
        }

        let cacheCreation = usage["cache_creation_input_tokens"] as? Int ?? 0
        let cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0
        let model = message["model"] as? String
        let cwd = json["cwd"] as? String
        let projectName = cwd.flatMap { URL(fileURLWithPath: $0).lastPathComponent }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.date(from: timestampStr) ?? Date()

        return TokenEvent(
            timestamp: timestamp,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheCreationTokens: cacheCreation,
            cacheReadTokens: cacheRead,
            model: model,
            projectName: projectName,
            source: name
        )
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

```bash
swift test --filter ClaudeCodeLogParserTests
```

Expected: PASS

- [ ] **Step 5: 커밋**

```bash
git add TokenGarden/Parsers/ClaudeCodeLogParser.swift TokenGardenTests/ClaudeCodeLogParserTests.swift
git commit -m "feat: implement ClaudeCodeLogParser for .jsonl log parsing"
```

---

## Chunk 3: Data Store & Log Watcher

### Task 6: TokenDataStore 서비스

**Files:**
- Create: `TokenGarden/Services/TokenDataStore.swift`
- Create: `TokenGardenTests/TokenDataStoreTests.swift`

- [ ] **Step 1: 테스트 작성**

`TokenGardenTests/TokenDataStoreTests.swift`:

```swift
import Testing
import SwiftData
@testable import TokenGarden

@Test func recordTokenEvent() async throws {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: DailyUsage.self, ProjectUsage.self, configurations: config)
    let store = TokenDataStore(modelContainer: container)

    let event = TokenEvent(
        timestamp: Date(),
        inputTokens: 100,
        outputTokens: 50,
        cacheCreationTokens: 200,
        cacheReadTokens: 30,
        model: "claude-opus-4-6",
        projectName: "my-project",
        source: "claude-code"
    )

    await store.record(event)

    let context = ModelContext(container)
    let descriptor = FetchDescriptor<DailyUsage>()
    let results = try context.fetch(descriptor)
    #expect(results.count == 1)
    #expect(results[0].inputTokens == 100)
    #expect(results[0].outputTokens == 50)
    #expect(results[0].cacheCreationTokens == 200)
    #expect(results[0].projectBreakdowns.count == 1)
    #expect(results[0].projectBreakdowns[0].projectName == "my-project")
}

@Test func recordMultipleEventsAccumulate() async throws {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: DailyUsage.self, ProjectUsage.self, configurations: config)
    let store = TokenDataStore(modelContainer: container)

    let event1 = TokenEvent(
        timestamp: Date(), inputTokens: 100, outputTokens: 50,
        cacheCreationTokens: 0, cacheReadTokens: 0,
        model: "claude-opus-4-6", projectName: "project-a", source: "claude-code"
    )
    let event2 = TokenEvent(
        timestamp: Date(), inputTokens: 200, outputTokens: 100,
        cacheCreationTokens: 0, cacheReadTokens: 0,
        model: "claude-opus-4-6", projectName: "project-a", source: "claude-code"
    )

    await store.record(event1)
    await store.record(event2)

    let context = ModelContext(container)
    let descriptor = FetchDescriptor<DailyUsage>()
    let results = try context.fetch(descriptor)
    #expect(results.count == 1)
    #expect(results[0].inputTokens == 300)
    #expect(results[0].outputTokens == 150)
    #expect(results[0].projectBreakdowns.count == 1)
    #expect(results[0].projectBreakdowns[0].tokens == 450)
}

@Test func fetchDailyUsagesForRange() async throws {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: DailyUsage.self, ProjectUsage.self, configurations: config)
    let store = TokenDataStore(modelContainer: container)

    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

    let event1 = TokenEvent(
        timestamp: today, inputTokens: 100, outputTokens: 50,
        cacheCreationTokens: 0, cacheReadTokens: 0,
        model: nil, projectName: nil, source: "claude-code"
    )
    let event2 = TokenEvent(
        timestamp: yesterday, inputTokens: 200, outputTokens: 100,
        cacheCreationTokens: 0, cacheReadTokens: 0,
        model: nil, projectName: nil, source: "claude-code"
    )

    await store.record(event1)
    await store.record(event2)

    let results = await store.fetchDailyUsages(from: yesterday, to: today)
    #expect(results.count == 2)
}
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
swift test --filter TokenDataStoreTests
```

Expected: FAIL

- [ ] **Step 3: TokenDataStore 구현**

`TokenGarden/Services/TokenDataStore.swift`:

```swift
import Foundation
import SwiftData

@MainActor
class TokenDataStore: ObservableObject {
    private let modelContainer: ModelContainer
    private let modelContext: ModelContext

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

        try? modelContext.save()
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
}
```

- [ ] **Step 4: 테스트 통과 확인**

```bash
swift test --filter TokenDataStoreTests
```

Expected: PASS

- [ ] **Step 5: 커밋**

```bash
git add TokenGarden/Services/TokenDataStore.swift TokenGardenTests/TokenDataStoreTests.swift
git commit -m "feat: add TokenDataStore with record and fetch operations"
```

---

### Task 7: LogWatcher (FSEvents 파일 감시)

**Files:**
- Create: `TokenGarden/Services/LogWatcher.swift`
- Create: `TokenGardenTests/LogWatcherTests.swift`

- [ ] **Step 1: 테스트 작성**

`TokenGardenTests/LogWatcherTests.swift`:

```swift
import Testing
import Foundation
@testable import TokenGarden

@Test func logWatcherDetectsNewContent() async throws {
    let projectRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
    let tempDir = projectRoot
        .appendingPathComponent(".claude/tmp/TokenGardenTest-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let logFile = tempDir.appendingPathComponent("test.jsonl")
    FileManager.default.createFile(atPath: logFile.path, contents: nil)

    var receivedLines: [String] = []
    let expectation = { receivedLines.count >= 1 }

    let watcher = LogWatcher(watchPaths: [tempDir.path]) { line in
        receivedLines.append(line)
    }
    watcher.start()
    defer { watcher.stop() }

    // Append a line to the log file
    let handle = try FileHandle(forWritingTo: logFile)
    handle.seekToEndOfFile()
    handle.write("{\"type\":\"assistant\"}\n".data(using: .utf8)!)
    handle.closeFile()

    // Wait for FSEvents (up to 3 seconds)
    for _ in 0..<30 {
        if expectation() { break }
        try await Task.sleep(nanoseconds: 100_000_000)
    }

    #expect(receivedLines.count >= 1)
    #expect(receivedLines[0].contains("assistant"))
}
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
swift test --filter LogWatcherTests
```

Expected: FAIL

- [ ] **Step 3: LogWatcher 구현**

`TokenGarden/Services/LogWatcher.swift`:

```swift
import Foundation

@MainActor
class LogWatcher {
    private let watchPaths: [String]
    private let onNewLine: @MainActor (String) -> Void
    private var stream: FSEventStreamRef?
    private var fileOffsets: [String: Int] = [:]
    private let offsetsKey = "LogWatcherOffsets"

    init(watchPaths: [String], onNewLine: @escaping @MainActor (String) -> Void) {
        self.watchPaths = watchPaths
        self.onNewLine = onNewLine
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
            0.5,  // 500ms latency
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
        saveOffsets()
    }

    private static let eventCallback: FSEventStreamCallback = { _, info, numEvents, eventPaths, _, _ in
        guard let info else { return }
        let watcher = Unmanaged<LogWatcher>.fromOpaque(info).takeUnretainedValue()
        guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }

        for path in paths {
            guard path.hasSuffix(".jsonl"),
                  !URL(fileURLWithPath: path).lastPathComponent.contains("compact") else { continue }
            watcher.processFile(at: path)
        }
    }

    private func processFile(at path: String) {
        guard FileManager.default.fileExists(atPath: path),
              let handle = FileHandle(forReadingAtPath: path) else { return }
        defer { handle.closeFile() }

        let fileSize = Int(handle.seekToEndOfFile())
        let offset = fileOffsets[path] ?? 0

        // File was truncated or replaced
        if offset > fileSize {
            fileOffsets[path] = 0
            handle.seek(toFileOffset: 0)
        } else {
            handle.seek(toFileOffset: UInt64(offset))
        }

        let data = handle.readDataToEndOfFile()
        fileOffsets[path] = Int(handle.offsetInFile)
        saveOffsets()

        guard let content = String(data: data, encoding: .utf8) else { return }
        let lines = content.components(separatedBy: .newlines)
        for line in lines where !line.isEmpty {
            onNewLine(line)
        }
    }

    /// Scan all existing .jsonl files for initial backfill
    func backfill() {
        for watchPath in watchPaths {
            let enumerator = FileManager.default.enumerator(atPath: watchPath)
            while let relativePath = enumerator?.nextObject() as? String {
                guard relativePath.hasSuffix(".jsonl"),
                      !relativePath.contains("compact") else { continue }
                let fullPath = (watchPath as NSString).appendingPathComponent(relativePath)
                if fileOffsets[fullPath] == nil {
                    processFile(at: fullPath)
                }
            }
        }
    }

    private func loadOffsets() {
        fileOffsets = UserDefaults.standard.dictionary(forKey: offsetsKey) as? [String: Int] ?? [:]
    }

    private func saveOffsets() {
        UserDefaults.standard.set(fileOffsets, forKey: offsetsKey)
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

```bash
swift test --filter LogWatcherTests
```

Expected: PASS

- [ ] **Step 5: 커밋**

```bash
git add TokenGarden/Services/LogWatcher.swift TokenGardenTests/LogWatcherTests.swift
git commit -m "feat: add LogWatcher with FSEvents file monitoring and backfill"
```

---

## Chunk 4: Number Formatter & Heatmap View

### Task 8: 토큰 수 포맷터

**Files:**
- Create: `TokenGarden/Utilities/NumberFormatter+Tokens.swift`
- Create: `TokenGardenTests/TokenFormatterTests.swift`

- [ ] **Step 1: 테스트 작성**

`TokenGardenTests/TokenFormatterTests.swift`:

```swift
import Testing
@testable import TokenGarden

@Test func formatSmallNumbers() {
    #expect(TokenFormatter.format(0) == "0")
    #expect(TokenFormatter.format(999) == "999")
}

@Test func formatThousands() {
    #expect(TokenFormatter.format(1000) == "1K")
    #expect(TokenFormatter.format(1500) == "1.5K")
    #expect(TokenFormatter.format(23400) == "23.4K")
    #expect(TokenFormatter.format(142000) == "142K")
}

@Test func formatMillions() {
    #expect(TokenFormatter.format(1_000_000) == "1M")
    #expect(TokenFormatter.format(1_200_000) == "1.2M")
}
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
swift test --filter TokenFormatterTests
```

Expected: FAIL

- [ ] **Step 3: TokenFormatter 구현**

`TokenGarden/Utilities/NumberFormatter+Tokens.swift`:

```swift
import Foundation

enum TokenFormatter {
    static func format(_ value: Int) -> String {
        if value < 1000 {
            return "\(value)"
        } else if value < 1_000_000 {
            let k = Double(value) / 1000.0
            if k.truncatingRemainder(dividingBy: 1) == 0 {
                return "\(Int(k))K"
            }
            let formatted = String(format: "%.1fK", k)
            return formatted.replacingOccurrences(of: ".0K", with: "K")
        } else {
            let m = Double(value) / 1_000_000.0
            if m.truncatingRemainder(dividingBy: 1) == 0 {
                return "\(Int(m))M"
            }
            let formatted = String(format: "%.1fM", m)
            return formatted.replacingOccurrences(of: ".0M", with: "M")
        }
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

```bash
swift test --filter TokenFormatterTests
```

Expected: PASS — 포맷 결과가 예상과 다르면 format 로직 조정

- [ ] **Step 5: 커밋**

```bash
git add TokenGarden/Utilities/NumberFormatter+Tokens.swift TokenGardenTests/TokenFormatterTests.swift
git commit -m "feat: add TokenFormatter for abbreviated token counts"
```

---

### Task 9: HeatmapView (잔디 히트맵)

**Files:**
- Create: `TokenGarden/Views/HeatmapView.swift`
- Create: `TokenGardenTests/HeatmapViewTests.swift`

- [ ] **Step 1: 히트맵 레벨 계산 로직 테스트 작성**

`TokenGardenTests/HeatmapViewTests.swift`:

```swift
import Testing
@testable import TokenGarden

@Test func heatmapLevelWithNoData() {
    let levels = HeatmapCalculator.calculateLevels(dailyTotals: [])
    #expect(levels.isEmpty)
}

@Test func heatmapLevelQuartiles() {
    // 12 days of data with varying usage
    let totals = [0, 100, 200, 300, 400, 500, 600, 700, 800, 900, 1000, 0]
    let levels = HeatmapCalculator.calculateLevels(dailyTotals: totals)

    #expect(levels.count == 12)
    // 0 usage = level 0
    #expect(levels[0] == 0)
    #expect(levels[11] == 0)
    // Non-zero values should be level 1-4
    #expect(levels[1] >= 1)
    #expect(levels[10] == 4)
}

@Test func heatmapLevelAllSameUsage() {
    let totals = [500, 500, 500, 500]
    let levels = HeatmapCalculator.calculateLevels(dailyTotals: totals)
    // All same = all level 4
    for level in levels {
        #expect(level == 4)
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
swift test --filter HeatmapViewTests
```

Expected: FAIL

- [ ] **Step 3: HeatmapCalculator & HeatmapView 구현**

`TokenGarden/Views/HeatmapView.swift`:

```swift
import SwiftUI

enum HeatmapCalculator {
    /// Returns an array of levels (0-4) for each daily total.
    /// 0 = no usage, 1-4 = quartile-based intensity.
    static func calculateLevels(dailyTotals: [Int]) -> [Int] {
        guard !dailyTotals.isEmpty else { return [] }

        let nonZero = dailyTotals.filter { $0 > 0 }.sorted()
        guard !nonZero.isEmpty else {
            return dailyTotals.map { _ in 0 }
        }

        let q1 = nonZero[nonZero.count / 4]
        let q2 = nonZero[nonZero.count / 2]
        let q3 = nonZero[nonZero.count * 3 / 4]

        return dailyTotals.map { total in
            if total == 0 { return 0 }
            if total <= q1 { return 1 }
            if total <= q2 { return 2 }
            if total <= q3 { return 3 }
            return 4
        }
    }
}

struct HeatmapView: View {
    let dailyUsages: [(date: Date, tokens: Int)]
    private let columns = 12  // weeks
    private let rows = 7      // days

    private let colors: [Color] = [
        Color(.systemGray).opacity(0.15),  // level 0: no usage
        Color.green.opacity(0.3),           // level 1
        Color.green.opacity(0.5),           // level 2
        Color.green.opacity(0.7),           // level 3
        Color.green,                         // level 4
    ]

    var body: some View {
        let levels = HeatmapCalculator.calculateLevels(
            dailyTotals: dailyUsages.map(\.tokens)
        )
        let grid = buildGrid(levels: levels)

        VStack(alignment: .leading, spacing: 2) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 2) {
                    ForEach(0..<columns, id: \.self) { col in
                        let index = col * rows + row
                        if index < grid.count {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(colors[grid[index].level])
                                .frame(width: 16, height: 16)
                                .help(grid[index].tooltip)
                        } else {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.gray.opacity(0.1))
                                .frame(width: 16, height: 16)
                        }
                    }
                }
            }
        }
    }

    private func buildGrid(levels: [Int]) -> [(level: Int, tooltip: String)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let totalDays = columns * rows

        // Build 84-day grid ending today
        var grid: [(level: Int, tooltip: String)] = []
        let startDate = calendar.date(byAdding: .day, value: -(totalDays - 1), to: today)!

        // Map dailyUsages by date for lookup
        var usageByDate: [Date: Int] = [:]
        for usage in dailyUsages {
            let day = calendar.startOfDay(for: usage.date)
            usageByDate[day] = (usageByDate[day] ?? 0) + usage.tokens
        }

        // Recalculate levels for the full grid
        var totals: [Int] = []
        for i in 0..<totalDays {
            let date = calendar.date(byAdding: .day, value: i, to: startDate)!
            totals.append(usageByDate[date] ?? 0)
        }
        let gridLevels = HeatmapCalculator.calculateLevels(dailyTotals: totals)

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium

        for i in 0..<totalDays {
            let date = calendar.date(byAdding: .day, value: i, to: startDate)!
            let tokens = totals[i]
            let level = i < gridLevels.count ? gridLevels[i] : 0
            let tooltip = "\(dateFormatter.string(from: date)): \(TokenFormatter.format(tokens))"
            grid.append((level: level, tooltip: tooltip))
        }

        return grid
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

```bash
swift test --filter HeatmapViewTests
```

Expected: PASS

- [ ] **Step 5: 커밋**

```bash
git add TokenGarden/Views/HeatmapView.swift TokenGardenTests/HeatmapViewTests.swift
git commit -m "feat: add HeatmapView with quartile-based color levels"
```

---

## Chunk 5: UI Views (Stats, ProjectList, EmptyState, Settings)

### Task 10: StatsView & ProjectListView

**Files:**
- Create: `TokenGarden/Views/StatsView.swift`
- Create: `TokenGarden/Views/ProjectListView.swift`

- [ ] **Step 1: StatsView 구현**

`TokenGarden/Views/StatsView.swift`:

```swift
import SwiftUI

struct StatsView: View {
    let todayTokens: Int
    let weekTokens: Int
    let monthTokens: Int
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("Today", systemImage: "chart.bar.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(TokenFormatter.format(todayTokens))
                    .font(.caption.monospacedDigit())
                    .fontWeight(.medium)

                Text(TokenFormatter.format(weekTokens))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture { withAnimation { isExpanded.toggle() } }

            if isExpanded {
                HStack {
                    VStack(alignment: .leading) {
                        Text("This Week").font(.caption2).foregroundStyle(.secondary)
                        Text(TokenFormatter.format(weekTokens)).font(.caption.monospacedDigit())
                    }
                    Spacer()
                    VStack(alignment: .leading) {
                        Text("This Month").font(.caption2).foregroundStyle(.secondary)
                        Text(TokenFormatter.format(monthTokens)).font(.caption.monospacedDigit())
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
```

- [ ] **Step 2: ProjectListView 구현**

`TokenGarden/Views/ProjectListView.swift`:

```swift
import SwiftUI

struct ProjectListView: View {
    let projects: [(name: String, tokens: Int)]
    @State private var isExpanded = false

    private var topProjects: [(name: String, tokens: Int)] {
        Array(projects.sorted { $0.tokens > $1.tokens }.prefix(3))
    }

    private var totalTokens: Int {
        projects.reduce(0) { $0 + $1.tokens }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("Projects", systemImage: "folder.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if !isExpanded {
                    Text("\(projects.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { withAnimation { isExpanded.toggle() } }

            let items = isExpanded ? projects.sorted(by: { $0.tokens > $1.tokens }) : topProjects
            ForEach(items, id: \.name) { project in
                HStack {
                    Text(project.name)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    let pct = totalTokens > 0 ? Int(Double(project.tokens) / Double(totalTokens) * 100) : 0
                    Text("\(pct)%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if !isExpanded && projects.count > 3 {
                Text("More...")
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .onTapGesture { withAnimation { isExpanded = true } }
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
```

- [ ] **Step 3: 빌드 확인**

```bash
swift build
```

Expected: 성공

- [ ] **Step 4: 커밋**

```bash
git add TokenGarden/Views/StatsView.swift TokenGarden/Views/ProjectListView.swift
git commit -m "feat: add StatsView and ProjectListView widgets"
```

---

### Task 11: EmptyStateView

**Files:**
- Create: `TokenGarden/Views/EmptyStateView.swift`

- [ ] **Step 1: EmptyStateView 구현**

`TokenGarden/Views/EmptyStateView.swift`:

```swift
import SwiftUI

enum EmptyStateReason {
    case noData
    case noPermission
    case noClaudeCode
}

struct EmptyStateView: View {
    let reason: EmptyStateReason

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if reason == .noPermission {
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var icon: String {
        switch reason {
        case .noData: "leaf.fill"
        case .noPermission: "lock.fill"
        case .noClaudeCode: "questionmark.folder.fill"
        }
    }

    private var title: String {
        switch reason {
        case .noData: "No Data Yet"
        case .noPermission: "Permission Required"
        case .noClaudeCode: "Logs Not Found"
        }
    }

    private var message: String {
        switch reason {
        case .noData:
            "Start using Claude Code and your token garden will grow here."
        case .noPermission:
            "Cannot access ~/.claude/ folder. Please grant permission in System Settings."
        case .noClaudeCode:
            "Claude Code log folder not found. Set the log path in Settings."
        }
    }
}
```

- [ ] **Step 2: 빌드 확인**

```bash
swift build
```

Expected: 성공

- [ ] **Step 3: 커밋**

```bash
git add TokenGarden/Views/EmptyStateView.swift
git commit -m "feat: add EmptyStateView for no-data, no-permission, no-claude states"
```

---

### Task 12: SettingsView

**Files:**
- Create: `TokenGarden/Views/SettingsView.swift`

- [ ] **Step 1: SettingsView 구현**

`TokenGarden/Views/SettingsView.swift`:

```swift
import SwiftUI
import ServiceManagement

enum MenuBarDisplayMode: String, CaseIterable {
    case iconOnly = "Icon Only"
    case iconAndNumber = "Icon + Tokens"
    case iconAndMiniGraph = "Icon + Mini Graph"
}

struct SettingsView: View {
    @AppStorage("logPath") private var logPath = "~/.claude/"
    @AppStorage("displayMode") private var displayMode = MenuBarDisplayMode.iconOnly.rawValue
    @AppStorage("animationEnabled") private var animationEnabled = true
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    var body: some View {
        Form {
            Section("Log Path") {
                HStack {
                    TextField("Path", text: $logPath)
                        .textFieldStyle(.roundedBorder)
                    Button("Browse...") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.allowsMultipleSelection = false
                        if panel.runModal() == .OK, let url = panel.url {
                            logPath = url.path
                        }
                    }
                }
            }

            Section("Menu Bar") {
                Picker("Display", selection: $displayMode) {
                    ForEach(MenuBarDisplayMode.allCases, id: \.rawValue) { mode in
                        Text(mode.rawValue).tag(mode.rawValue)
                    }
                }
                Toggle("Animation", isOn: $animationEnabled)
            }

            Section("General") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = !newValue
                        }
                    }
            }

            Section {
                Button("Quit Token Garden") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 320)
        .padding()
    }
}
```

- [ ] **Step 2: 빌드 확인**

```bash
swift build
```

Expected: 성공

- [ ] **Step 3: 커밋**

```bash
git add TokenGarden/Views/SettingsView.swift
git commit -m "feat: add SettingsView with log path, display mode, and launch options"
```

---

## Chunk 6: Menu Bar Animation & Integration

### Task 13: MenuBarController & Animation

**Files:**
- Create: `TokenGarden/MenuBar/MenuBarController.swift`
- Create: `TokenGarden/MenuBar/AnimationFrames.swift`

- [ ] **Step 1: AnimationFrames 구현**

`TokenGarden/MenuBar/AnimationFrames.swift`:

```swift
import AppKit

enum AnimationFrames {
    /// SF Symbol names for plant growth animation
    static let frames = [
        "leaf.fill",           // seed/sprout
        "leaf.arrow.triangle.circlepath",  // growing
        "tree.fill",           // tree
        "sparkles",            // bloom
    ]

    static func image(for index: Int) -> NSImage? {
        let name = frames[index % frames.count]
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Token Garden")
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        return image?.withSymbolConfiguration(config)
    }
}
```

- [ ] **Step 2: MenuBarController 구현**

`TokenGarden/MenuBar/MenuBarController.swift`:

```swift
import AppKit
import Combine

enum AnimationSpeed: TimeInterval {
    case slow = 1.0    // 1 fps
    case medium = 0.33 // 3 fps
    case fast = 0.167  // 6 fps
}

@MainActor
class MenuBarController: ObservableObject {
    @Published var todayTokens: Int = 0

    private var animationTimer: Timer?
    private var idleTimer: Timer?
    private var currentFrame = 0
    private var recentTokens: [(date: Date, count: Int)] = []
    private weak var statusItem: NSStatusItem?

    private let animationEnabled: () -> Bool
    private let displayMode: () -> String

    init(
        statusItem: NSStatusItem,
        initialTodayTokens: Int = 0,
        animationEnabled: @escaping () -> Bool = { UserDefaults.standard.bool(forKey: "animationEnabled") },
        displayMode: @escaping () -> String = { UserDefaults.standard.string(forKey: "displayMode") ?? MenuBarDisplayMode.iconOnly.rawValue }
    ) {
        self.statusItem = statusItem
        self.todayTokens = initialTodayTokens
        self.animationEnabled = animationEnabled
        self.displayMode = displayMode
        updateDisplay()
    }

    func onTokenEvent(_ event: TokenEvent) {
        todayTokens += event.totalTokens
        recentTokens.append((date: Date(), count: event.totalTokens))
        recentTokens.removeAll { Date().timeIntervalSince($0.date) > 30 }

        updateDisplay()

        guard animationEnabled() else { return }
        updateAnimationSpeed()
        resetIdleTimer()
    }

    private func updateDisplay() {
        guard let button = statusItem?.button else { return }
        let mode = MenuBarDisplayMode(rawValue: displayMode()) ?? .iconOnly

        switch mode {
        case .iconOnly:
            button.title = ""
        case .iconAndNumber:
            button.title = " \(TokenFormatter.format(todayTokens))"
        case .iconAndMiniGraph:
            button.title = "" // TODO: mini graph in future
        }

        if animationTimer == nil {
            button.image = AnimationFrames.image(for: 0)
        }
    }

    private func startAnimation(speed: AnimationSpeed) {
        animationTimer?.invalidate()
        animationTimer = Timer.scheduledTimer(withTimeInterval: speed.rawValue, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.advanceFrame()
            }
        }
    }

    private func updateAnimationSpeed() {
        let speed = currentSpeed()
        startAnimation(speed: speed)
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        currentFrame = 0
        statusItem?.button?.image = AnimationFrames.image(for: 0)
    }

    private func advanceFrame() {
        currentFrame = (currentFrame + 1) % AnimationFrames.frames.count
        statusItem?.button?.image = AnimationFrames.image(for: currentFrame)
    }

    private func resetIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.stopAnimation()
            }
        }
    }

    private func currentSpeed() -> AnimationSpeed {
        let recentTotal = recentTokens
            .filter { Date().timeIntervalSince($0.date) <= 30 }
            .reduce(0) { $0 + $1.count }

        if recentTotal > 10_000 { return .fast }
        if recentTotal > 1_000 { return .medium }
        return .slow
    }
}
```

- [ ] **Step 3: 빌드 확인**

```bash
swift build
```

Expected: 성공

- [ ] **Step 4: 커밋**

```bash
git add TokenGarden/MenuBar/AnimationFrames.swift TokenGarden/MenuBar/MenuBarController.swift
git commit -m "feat: add MenuBarController with RunCat-style plant animation"
```

---

### Task 14: 전체 통합 (PopoverView + AppDelegate 연결)

**Files:**
- Modify: `TokenGarden/Views/PopoverView.swift`
- Modify: `TokenGarden/AppDelegate.swift`
- Modify: `TokenGarden/TokenGardenApp.swift`

- [ ] **Step 1: PopoverView 완성**

`TokenGarden/Views/PopoverView.swift` 를 아래로 교체:

```swift
import SwiftUI
import SwiftData

struct PopoverView: View {
    @EnvironmentObject var menuBarController: MenuBarController
    @Query(sort: \DailyUsage.date) private var allUsages: [DailyUsage]
    @State private var showSettings = false

    private var todayUsage: DailyUsage? {
        let today = Calendar.current.startOfDay(for: Date())
        return allUsages.first { $0.date == today }
    }

    private var weekTokens: Int {
        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date())!
        return allUsages
            .filter { $0.date >= calendar.startOfDay(for: weekAgo) }
            .reduce(0) { $0 + $1.totalTokens }
    }

    private var monthTokens: Int {
        let calendar = Calendar.current
        let monthAgo = calendar.date(byAdding: .month, value: -1, to: Date())!
        return allUsages
            .filter { $0.date >= calendar.startOfDay(for: monthAgo) }
            .reduce(0) { $0 + $1.totalTokens }
    }

    private var heatmapData: [(date: Date, tokens: Int)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -83, to: today)!
        return allUsages
            .filter { $0.date >= start }
            .map { (date: $0.date, tokens: $0.totalTokens) }
    }

    private var projectData: [(name: String, tokens: Int)] {
        var totals: [String: Int] = [:]
        for usage in allUsages {
            for project in usage.projectBreakdowns {
                totals[project.projectName, default: 0] += project.tokens
            }
        }
        return totals.map { (name: $0.key, tokens: $0.value) }
    }

    private var emptyStateReason: EmptyStateReason? {
        let logPath = UserDefaults.standard.string(forKey: "logPath") ?? "~/.claude/"
        let expandedPath = NSString(string: logPath).expandingTildeInPath

        if !FileManager.default.fileExists(atPath: expandedPath) {
            return .noClaudeCode
        }
        if !FileManager.default.isReadableFile(atPath: expandedPath) {
            return .noPermission
        }
        if allUsages.isEmpty {
            return .noData
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Token Garden")
                    .font(.headline)
                Spacer()
                Button(action: { showSettings.toggle() }) {
                    Image(systemName: "gearshape")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            if let reason = emptyStateReason {
                EmptyStateView(reason: reason)
            } else if showSettings {
                SettingsView()
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        HeatmapView(dailyUsages: heatmapData)
                            .padding(.horizontal, 12)
                            .padding(.top, 8)

                        StatsView(
                            todayTokens: todayUsage?.totalTokens ?? 0,
                            weekTokens: weekTokens,
                            monthTokens: monthTokens
                        )
                        .padding(.horizontal, 12)

                        if !projectData.isEmpty {
                            ProjectListView(projects: projectData)
                                .padding(.horizontal, 12)
                        }
                    }
                    .padding(.bottom, 12)
                }
            }
        }
        .frame(width: 320, height: 400)
    }
}
```

- [ ] **Step 2: AppDelegate 통합**

`TokenGarden/AppDelegate.swift` 를 아래로 교체:

```swift
import AppKit
import SwiftUI
import SwiftData

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var menuBarController: MenuBarController!
    private var logWatcher: LogWatcher!
    private var dataStore: TokenDataStore!
    private var modelContainer: ModelContainer!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // SwiftData
        modelContainer = try! ModelContainer(for: DailyUsage.self, ProjectUsage.self)
        dataStore = TokenDataStore(modelContainer: modelContainer)

        // Status Item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "leaf.fill", accessibilityDescription: "Token Garden")
            button.action = #selector(togglePopover)
            button.target = self
        }

        // MenuBar Controller — load today's tokens from store
        let todayTokens = dataStore.fetchDailyUsages(
            from: Calendar.current.startOfDay(for: Date()),
            to: Date()
        ).first?.totalTokens ?? 0
        menuBarController = MenuBarController(statusItem: statusItem, initialTodayTokens: todayTokens)

        // Popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 400)
        popover.behavior = .transient

        let popoverView = PopoverView()
            .environmentObject(menuBarController)
            .modelContainer(modelContainer)
        popover.contentViewController = NSHostingController(rootView: popoverView)

        // Log Parser + Watcher
        let parser = ClaudeCodeLogParser()
        logWatcher = LogWatcher(watchPaths: parser.watchPaths) { [weak self] line in
            guard let event = parser.parse(logLine: line) else { return }
            Task { @MainActor in
                self?.dataStore.record(event)
                self?.menuBarController.onTokenEvent(event)
            }
        }

        // Backfill existing logs, then start watching
        logWatcher.backfill()
        logWatcher.start()
    }

    @objc func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}
```

- [ ] **Step 3: TokenGardenApp.swift 업데이트**

`TokenGarden/TokenGardenApp.swift` 를 아래로 교체:

```swift
import SwiftUI
import SwiftData

@main
struct TokenGardenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
```

- [ ] **Step 4: 빌드 확인**

```bash
swift build
```

Expected: 성공

- [ ] **Step 5: 앱 실행하여 수동 테스트**

```bash
swift run
```

확인 사항:
- 메뉴바에 잎사귀 아이콘 표시
- 클릭 시 팝오버 열림
- 기존 Claude Code 로그가 있으면 잔디 히트맵에 데이터 표시
- 설정(톱니바퀴) 클릭 시 설정 뷰 표시

- [ ] **Step 6: 커밋**

```bash
git add TokenGarden/Views/PopoverView.swift TokenGarden/AppDelegate.swift TokenGarden/TokenGardenApp.swift
git commit -m "feat: integrate all components into working menu bar app"
```

---

## Chunk 7: Polish & Final Verification

### Task 15: 전체 테스트 실행 & 수정

- [ ] **Step 1: 전체 테스트 실행**

```bash
swift test
```

Expected: 모든 테스트 통과

- [ ] **Step 2: 실패하는 테스트가 있으면 수정**

실패 원인 분석 후 수정. 수정 후 다시 `swift test` 실행하여 전체 통과 확인.

- [ ] **Step 3: 앱 실행하여 E2E 수동 테스트**

```bash
swift run
```

체크리스트:
- [ ] 메뉴바 아이콘 표시됨
- [ ] 팝오버 열림/닫힘
- [ ] 잔디 히트맵 표시 (기존 로그 데이터 있을 경우)
- [ ] 통계 위젯 표시
- [ ] 프로젝트 목록 표시
- [ ] 설정 뷰 동작
- [ ] 빈 상태 표시 (해당 시)

- [ ] **Step 4: 최종 커밋**

```bash
git add -A
git commit -m "chore: polish and verify Token Garden v1"
```
