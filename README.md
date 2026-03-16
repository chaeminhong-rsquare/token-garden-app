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

```
TokenGarden/
├── AppDelegate.swift              # 앱 초기화, 메뉴바, 팝오버
├── MenuBar/
│   ├── MenuBarController.swift    # 상태바 표시 (아이콘/텍스트/그래프)
│   └── AnimationFrames.swift      # 식물 성장 애니메이션 (5프레임)
├── Services/
│   ├── TokenDataStore.swift       # SwiftData 저장소
│   ├── LogWatcher.swift           # FSEventStream 파일 감시
│   └── UpdateChecker.swift        # GitHub release 업데이트 체크
├── Parsers/
│   └── ClaudeCodeLogParser.swift  # JSONL 로그 파싱
├── Models/
│   ├── DailyUsage.swift           # 일별 집계 (@Model)
│   ├── SessionUsage.swift         # 세션 추적 (@Model)
│   ├── ProjectUsage.swift         # 프로젝트별 집계 (@Model)
│   ├── TokenEvent.swift           # 파싱된 이벤트
│   └── HeatmapTheme.swift        # 컬러 테마
└── Views/
    ├── PopoverView.swift          # 메인 팝오버
    ├── HeatmapView.swift          # 캘린더 히트맵
    ├── StatsView.swift            # 통계 카드
    ├── ProjectListView.swift      # 프로젝트 목록
    ├── SessionListView.swift      # 활성 세션 목록
    └── SettingsView.swift         # 설정
```

## License

MIT
