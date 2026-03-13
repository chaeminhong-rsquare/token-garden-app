# Token Garden - macOS Menu Bar App Design Spec

## Overview

GitHub 잔디(contribution graph) 스타일로 AI 토큰 사용량을 시각화하는 macOS 네이티브 메뉴바 앱.
Claude Code 로그 기반으로 시작하되, 프로토콜 추상화를 통해 다른 LLM 도구로 확장 가능한 구조.

## Tech Stack

- **언어/프레임워크**: Swift + SwiftUI
- **최소 지원 버전**: macOS 14 (Sonoma)
- **데이터 저장**: SwiftData (로컬)
- **파일 감시**: FSEvents
- **앱 타입**: LSUIElement (Dock 아이콘 없음, 메뉴바 전용)

## Architecture

단일 앱 구조. 모든 컴포넌트가 하나의 프로세스에서 동작.

```
┌─────────────────────────────────┐
│         TokenGardenApp          │
│  (NSApplicationDelegateAdaptor) │
├─────────────────────────────────┤
│  MenuBarController              │  ← NSStatusItem 관리, 애니메이션
│  PopoverView                    │  ← 메인 SwiftUI 팝오버
├─────────────────────────────────┤
│  TokenDataStore                 │  ← 일별/프로젝트별 집계, SwiftData
├─────────────────────────────────┤
│  LogWatcher                     │  ← FSEvents로 로그 파일 변경 감지
│  protocol TokenLogParser        │  ← 파서 추상화
│    ├─ ClaudeCodeLogParser       │  ← ~/.claude/ 로그 파싱
│    └─ (향후 다른 파서 추가)       │
└─────────────────────────────────┘
```

## Components

### 1. MenuBarController

NSStatusItem을 관리하는 컨트롤러.

**표시 모드 (설정에서 선택):**

| 모드 | 표시 | 설명 |
|------|------|------|
| 아이콘만 | 🌱 | 정적 식물 아이콘 |
| 아이콘 + 숫자 | 🌱 12.3K | 오늘 토큰 사용량 |
| 아이콘 + 미니잔디 | 🌱▁▃▅▂▇ | 최근 7일 막대 그래프 |

**애니메이션:**
- 토큰 사용 감지 시 식물 성장 프레임 애니메이션 (씨앗 → 새싹 → 꽃)
- 사용량이 많을수록 애니메이션 속도 증가 (RunCat 방식)
- 비활성 시 정적 아이콘으로 복귀
- SF Symbols 기반 프레임 구성
- 설정에서 on/off 가능

**애니메이션 타이밍:**
- **트리거**: LogWatcher가 새로운 `type: "assistant"` 라인 감지 시 시작
- **속도 단계**: 최근 30초 내 토큰 수 기준 — <1K: 느림(1fps), 1K-10K: 보통(3fps), >10K: 빠름(6fps)
- **종료**: 마지막 토큰 이벤트 후 5초간 유지, 이후 정적 아이콘으로 복귀

### 2. PopoverView

메뉴바 아이콘 클릭 시 표시되는 팝오버. 약 320x400pt.

```
┌─────────────────────────────────────┐
│  Token Garden          ⚙️ (설정)    │
├─────────────────────────────────────┤
│                                     │
│  ┌─ 잔디 히트맵 (메인) ───────────┐ │
│  │  GitHub 스타일 12주 그리드      │ │
│  │  월 화 수 목 금 토 일           │ │
│  │  □ □ ■ □ ■ ■ □  ← 색상 농도   │ │
│  │  □ ■ ■ ■ □ □ □     = 사용량    │ │
│  └────────────────────────────────┘ │
│                                     │
│  ┌─ 미니 위젯들 ─────────────────┐ │
│  │ 📊 오늘 23.4K  이번주 142K    │ │
│  │ 📁 token-garden-app  58%      │ │
│  │    rtb-api            32%      │ │
│  └────────────────── [더보기 ▸] ──┘ │
└─────────────────────────────────────┘
```

**잔디 히트맵 (메인 영역):**
- GitHub 스타일 12주 그리드 (v1에서는 고정, 스크롤 없음)
- 색상 농도로 사용량 표현 (연두 → 진녹)
- **색상 기준**: 해당 12주 데이터의 사분위수(quartile) 기반 (GitHub 방식). 사용량 0 = 빈 칸, 1-25% = level 1, 26-50% = level 2, 51-75% = level 3, 76-100% = level 4
- **데이터 없는 날 vs 0 사용**: 앱 설치 이전 = 회색, 0 사용 = 빈 칸(배경색)으로 구분
- 칸 hover 시 날짜 + 토큰 사용량 툴팁

**미니 위젯:**
- 요약 통계: 오늘/이번주/이번달 토큰 수 — 작게 표시, 클릭 시 상세 확장
- 프로젝트별: 상위 2-3개 프로젝트 비율 — 클릭 시 전체 목록 확장
- 숫자 포맷: 약식 표기 (23.4K, 1.2M)

**빈 상태 (Empty State):**
- 데이터 없음: "아직 토큰 사용 기록이 없습니다. Claude Code를 사용하면 여기에 잔디가 자랍니다 🌱"
- 권한 없음: "~/.claude/ 폴더에 접근할 수 없습니다. 시스템 설정에서 권한을 확인해주세요." + 시스템 설정 열기 버튼
- Claude Code 미설치 (~/.claude/ 없음): "Claude Code 로그 폴더를 찾을 수 없습니다. 설정에서 로그 경로를 지정해주세요."

### 3. TokenDataStore

SwiftData 기반 로컬 데이터 저장소.

**모델:**

```swift
@Model
class DailyUsage {
    @Attribute(.unique) var date: Date  // 시스템 로컬 타임존 기준, 시간 제거
    var totalTokens: Int
    var inputTokens: Int
    var outputTokens: Int
    var cacheCreationTokens: Int
    var cacheReadTokens: Int
    var projectBreakdowns: [ProjectUsage]
}

@Model
class ProjectUsage {
    var projectName: String
    var tokens: Int
    var model: String?           // e.g., "claude-opus-4-6"
    var dailyUsage: DailyUsage?  // 역관계 (date는 DailyUsage에서 참조)
}
```

**결정 사항:**
- `totalTokens` = inputTokens + outputTokens (cache 토큰은 별도 필드로 저장, 합산하지 않음)
- cache 토큰은 참고용으로 저장하되, 잔디 히트맵/통계에는 input+output만 사용
- `model` 필드를 ProjectUsage에 포함하여 향후 비용 추정 기능 대비
- 날짜 기준: 시스템 로컬 타임존

### 4. LogWatcher

FSEvents 기반 파일 변경 감시.

- `TokenLogParser.watchPaths`에 등록된 경로를 **재귀적으로** 감시 (새 세션 파일, 새 프로젝트 디렉토리 포함)
- 파일 변경 감지 시 해당 파서에 새 라인 전달
- 증분 파싱: 파일별 마지막 읽은 위치(offset)를 UserDefaults에 저장
- **새 파일 감지**: 새로운 `.jsonl` 파일 발견 시 offset 0부터 시작
- **파일 변경 대응**: 저장된 offset > 현재 파일 크기면 offset을 0으로 리셋 (파일 교체/truncate 대응)
- **스레드 안전**: FSEvents 콜백에서 파싱 후 `@MainActor`를 통해 SwiftData에 전달

**첫 실행 백필:**
- 기존 로그를 백그라운드에서 최신순으로 파싱
- 팝오버에 "기존 데이터 불러오는 중... (X/Y)" 프로그레스 표시
- UI는 즉시 사용 가능 — 데이터가 채워지는 대로 히트맵 업데이트

### 5. TokenLogParser Protocol

```swift
protocol TokenLogParser {
    var name: String { get }
    var watchPaths: [String] { get }
    func parse(logLine: String) -> TokenEvent?
}

struct TokenEvent {
    let timestamp: Date
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    let model: String?
    let projectName: String?
    let source: String  // e.g., "claude-code"
}
```

### 6. ClaudeCodeLogParser

`TokenLogParser` 프로토콜의 첫 번째 구현체.

- **감시 경로**: `~/.claude/projects/` 하위 전체 (재귀)
- **파싱 대상**: `type == "assistant"` 라인만 필터, `message.usage` 에서 토큰 추출
  - `input_tokens`, `output_tokens`: 기본 토큰
  - `cache_creation_input_tokens`, `cache_read_input_tokens`: 캐시 토큰
- **subagent 로그**: `subagents/` 디렉토리 포함하여 파싱 (부모 세션은 subagent 토큰을 별도 집계하지 않으므로 중복 없음)
- **compact 로그**: `*compact*.jsonl` 파일은 스킵 (중복 방지)
- **프로젝트명**: 로그 라인의 `cwd` 필드에서 추출 (디렉토리명 파싱보다 정확). fallback으로 디렉토리 경로의 마지막 세그먼트 사용

## Permissions

- `~/.claude/` 읽기 권한 필요
- macOS에서 별도 Full Disk Access가 필요할 수 있음 (홈 디렉토리 하위이므로 대부분 기본 허용)
- 앱 시작 시 경로 접근 가능 여부 체크 → 불가 시 빈 상태 UI 표시
- 자동 시작: SMAppService (macOS 13+) 사용, 시스템 설정의 로그인 항목에서 사용자 확인 필요

## Settings (v1)

- 로그 경로 설정 (기본값: `~/.claude/`)
- 메뉴바 표시 모드 선택 (아이콘만 / 숫자 / 미니잔디)
- 애니메이션 on/off
- 로그인 시 자동 시작

## Future TODO

- [ ] 시간 단위, 세션 단위 잔디 뷰
- [ ] 히트맵 12주 이전 기간 스크롤/네비게이션
- [ ] 잔디 색상 테마 커스터마이징
- [ ] 토큰 사용량 알림 (일일 한도 초과 등)
- [ ] 비용 추정 기능 (model 필드 활용)
- [ ] 단축키 설정
- [ ] 데이터 내보내기 (CSV/JSON)
- [ ] 다른 LLM 도구 파서 추가 (Cursor, Copilot 등)
