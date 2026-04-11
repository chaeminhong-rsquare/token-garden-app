# Token Garden

Claude Code 토큰 사용량을 추적하는 macOS 메뉴바 앱.

`~/.claude/` 로그를 실시간 파싱하여 히트맵, 프로젝트별 통계, 활성 세션을 보여줍니다.

## Features

- **Heatmap** — 일별 토큰 사용량을 GitHub 스타일 히트맵으로 표시 (D/W/M/Y 뷰)
- **Stats** — 오늘/이번 주/이번 달 토큰 합계
- **Projects** — 프로젝트별 사용량 및 비율
- **Active Sessions** — 현재 실행 중인 Claude 세션 실시간 추적
- **Menu Bar** — 아이콘 / 아이콘+토큰 수 / 아이콘+미니 그래프 모드
- **Color Themes** — 8가지 히트맵 컬러 테마 (Green, Blue, Purple, Orange, Red, Yellow, Pink, Rainbow)
- **Auto Update** — GitHub Releases에서 새 버전 자동 확인

## Install

[Releases](https://github.com/chaeminhong-rsquare/token-garden-app/releases)에서 DMG 다운로드 후 Applications에 드래그.

## Requirements

- macOS 14.0+

## Build

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -scheme TokenGarden -destination 'platform=macOS' \
  -derivedDataPath .claude/tmp/DerivedData \
  -configuration Release build
```

배포 방법은 [DEPLOY.md](DEPLOY.md) 참고.

## Architecture

Overview 탭은 **데이터 레이어와 UI 레이어가 분리된 MVVM 구조**로 동작합니다. 메뉴바 클릭 시 SwiftData fetch가 main thread를 막지 않도록, VM이 앱 시작 시 백그라운드에서 미리 데이터를 로드합니다.

```
┌─────────────────────────────────────────────────────────┐
│ UI Layer  (Views, dumb)                                 │
│   PopoverView → VM의 snapshot을 읽기만 함                 │
│   · HeatmapView, StatsView, HourlyChartView, ...        │
└─────────────────────────────────────────────────────────┘
                    ↑ OverviewSnapshot (Sendable)
┌─────────────────────────────────────────────────────────┐
│ ViewModel Layer  (@Observable, @MainActor)              │
│   OverviewViewModel — isInitialLoading, snapshot,       │
│                       selectedDate, active hourly       │
└─────────────────────────────────────────────────────────┘
                    ↑ await repo.loadSnapshot()
┌─────────────────────────────────────────────────────────┐
│ Repository Layer  (@ModelActor, background executor)    │
│   OverviewRepository — SwiftData fetch + aggregation    │
│                        → returns Sendable snapshot      │
└─────────────────────────────────────────────────────────┘
```

```
TokenGarden/
├── AppDelegate.swift              # 앱 초기화, VM 생성/주입, 메뉴바, 팝오버
├── MenuBar/
│   ├── MenuBarController.swift    # 상태바 표시 (아이콘/텍스트/그래프)
│   └── AnimationFrames.swift      # 식물 성장 애니메이션 (5프레임)
├── Services/
│   ├── TokenDataStore.swift       # SwiftData 쓰기 경로 (record + flush)
│   ├── OverviewRepository.swift   # @ModelActor 읽기 경로, Snapshot 생성
│   ├── LogWatcher.swift           # FSEventStream 파일 감시
│   └── UpdateChecker.swift        # GitHub release 업데이트 체크
├── ViewModels/
│   └── OverviewViewModel.swift    # @Observable, Overview 탭 상태 관리
├── Parsers/
│   └── ClaudeCodeLogParser.swift  # JSONL 로그 파싱
├── Models/
│   ├── DailyUsage.swift           # 일별 집계 (@Model)
│   ├── SessionUsage.swift         # 세션 추적 (@Model)
│   ├── ProjectUsage.swift         # 프로젝트별 집계 (@Model)
│   ├── HourlyUsage.swift          # 시간대별 집계 (@Model)
│   ├── OverviewSnapshot.swift     # Sendable value type (UI가 읽는 데이터)
│   ├── TokenEvent.swift           # 파싱된 이벤트
│   └── HeatmapTheme.swift         # 컬러 테마
├── Utilities/
│   ├── ExpandAnimation.swift      # 섹션 펼치기/접기 공통 애니메이션
│   ├── DebouncedPersistence.swift # 저장 debounce
│   └── ProcessRunner.swift        # 외부 프로세스 실행
└── Views/
    ├── PopoverView.swift          # 메인 팝오버 (탭 컨테이너, 고정 높이)
    ├── PulseSkeleton.swift        # 로딩 중 placeholder (pulse 애니메이션)
    ├── HeatmapView.swift          # 캘린더 히트맵
    ├── StatsView.swift            # 통계 카드
    ├── HourlyChartView.swift      # 시간대별 차트
    ├── ProjectListView.swift      # 프로젝트 목록
    ├── SessionListView.swift      # 활성 세션 목록
    ├── AccountsTabView.swift      # 계정별 사용량 탭
    └── SettingsView.swift         # 설정
```

## Testing

Swift Testing 기반 단위 테스트. `xcodebuild test`로 실행:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test -scheme TokenGarden -destination 'platform=macOS' \
  -derivedDataPath .claude/tmp/DerivedData
```

테스트는 in-memory `ModelContainer`를 사용해 실제 DB 없이 실행됩니다.

## License

MIT
