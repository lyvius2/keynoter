# Keynoter

> [원문](./README.md)

**Apple Keynote를 위한 온디바이스 AI 프레젠테이션 에이전트.**

Keynoter는 Apple의 온디바이스 Foundation Models를 사용해 Apple Keynote
프레젠테이션을 생성하고 편집하는 macOS 네이티브 대화형 CLI입니다.

모든 슬라이드를 일일이 손으로 조작하는 대신, 자연어로 Keynoter와 대화하며
작업합니다:

``` text
$ keynoter

> /create msk-migration

✓ Created msk-migration.key

> Create an 8-slide presentation about AWS MSK Migration Architecture
  for software engineers. Include AS-IS, TO-BE, and Migration Strategy.

Planning presentation...
Generating slides...
Applying changes to Keynote...

✓ Done.
```

## 콘셉트

Keynoter는 에이전트 방식의 CLI와 네이티브 macOS 자동화를 결합합니다:

``` mermaid
flowchart LR
    U[User] --> K[Keynoter CLI]
    K --> FM[Apple Foundation Models]
    FM --> A[Structured Actions]
    A --> S[Swift Action Engine]
    S --> AS[AppleScript]
    AS --> KN[Keynote]
    KN --> F[".key"]
```

언어 모델은 **무엇을 바꿀지**를 결정합니다.

Keynoter의 Swift 런타임은 **그 변경을 Keynote에 어떻게 안전하게 적용할지**를
결정합니다.

## 왜 Keynoter인가?

Keynote는 본질적으로 macOS 애플리케이션이며, 그렇기에 Apple의 온디바이스
모델은 AI 프레젠테이션 워크플로에 자연스럽게 들어맞습니다.

Keynoter는 다음을 중심으로 설계되었습니다:

-   Apple Foundation Models / Apple Intelligence
-   온디바이스 추론
-   Swift
-   AppleScript / Apple Events
-   Apple Keynote
-   대화형 에이전트 CLI 경험

주요 워크플로는 Ollama나 외부 추론 서버를 필요로 하지 않습니다.

## CLI

MVP 예정 명령어:

| 명령어 | 설명 |
|---|---|
| `/help` | 사용 가능한 명령어 표시 |
| `/create {filename}` | 새 Keynote 프레젠테이션 생성 |
| `/edit {path}` | 기존 Keynote 프레젠테이션 편집 시작 |
| `/status` | 현재 세션 및 문서 상태 표시 |
| `/open` | Keynote에서 활성 문서를 열거나 포커스 |
| `/save` | 활성 프레젠테이션 저장 |
| `/save-as {filename}` | 다른 이름으로 프레젠테이션 저장 |
| `/undo` | 마지막 Keynoter 작업 되돌리기 |
| `/redo` | 마지막으로 되돌린 작업 다시 적용 |
| `/script` | 마지막 작업에서 생성된 AppleScript 표시 |
| `/doctor` | 로컬 Keynoter 환경 점검 |
| `/close` | 활성 문서 세션 닫기 |
| `/exit` | Keynoter 종료 |

프레젠테이션 내용의 변경은 명령어가 아니라 자연어로 표현합니다:

``` text
> Add a TO-BE Architecture slide after slide 3.

> Slide 4 has too much text. Keep only the three most important points.

> Delete slide 5.

> Rewrite the presentation for an executive audience.
```

## 설계에 의한 안전성 (Safety by Design)

Keynoter는 언어 모델에게 임의의 AppleScript를 생성하게 하고 그것을 그대로
실행하는 방식을 **취하지 않습니다**.

의도된 파이프라인은 다음과 같습니다:

``` text
Prompt
  ↓
Apple Foundation Models
  ↓
Structured PresentationAction
  ↓
Validation
  ↓
Swift Action Engine
  ↓
Deterministic AppleScript Renderer
  ↓
Keynote
```

이 구조는 모델의 추론을 애플리케이션 실행과 분리하고, 생성된 자동화를
`/script`를 통해 확인할 수 있게 합니다.

## 기술

-   **플랫폼:** macOS
-   **언어:** Swift
-   **빌드:** Swift Package Manager
-   **AI:** Apple Foundation Models 프레임워크
-   **프레젠테이션:** Apple Keynote
-   **자동화:** AppleScript / Apple Events
-   **인터페이스:** 대화형 CLI / REPL

Xcode가 반드시 필요합니다. FoundationModels 프레임워크는 Xcode에 포함된
macOS 26 SDK에서 제공되며, Command Line Tools만으로는 이 패키지를 빌드할 수
없습니다. 다만 Xcode를 주 편집기로 사용할 필요는 없습니다.

## 프로젝트 현황

Keynoter는 **초기 개발 단계**에 있습니다. 대화형 셸은 현재 동작하며 모든
명령어를 파싱하고 디스패치하지만, Keynote를 실제로 조작하는 핸들러는 아직
스텁 상태입니다.

구현 마일스톤:

-   [x] 대화형 CLI / REPL — 명령어 파싱, 디스패치, 세션 상태
-   [ ] 환경 진단 (`/doctor`, `/status`)
-   [ ] Keynote 문서 생성 및 편집
-   [ ] 저장/열기/세션 관리
-   [ ] 구조화된 `PresentationAction` 생성 및 검증
-   [ ] 결정론적 AppleScript 렌더링
-   [ ] undo/redo
-   [ ] AppleScript 확인 (`/script`)
-   [ ] Foundation Models 통합

PDF 및 PowerPoint 내보내기, 더 풍부한 레이아웃, 다이어그램, 이미지, 테마,
프레젠테이션 템플릿은 이후 단계로 계획되어 있습니다.

## 개발

``` bash
swift build          # 빌드
swift run keynoter   # REPL 실행
swift test           # 테스트 실행
```

`swift build`가 매니페스트 컴파일 단계에서 실패한다면 활성 툴체인이 Xcode가
아니라 Command Line Tools인 경우입니다. 한 번만 Xcode로 전환하면 됩니다:

``` bash
sudo xcode-select -s /Applications/Xcode.app
```

패키지 구조 — 단계(Phase)가 표시된 디렉터리는 아직 존재하지 않습니다:

``` text
keynoter/
├── Package.swift
├── CLAUDE.md · CLAUDE_KR.md     — 개발자 가이드
├── AGENTS.md
├── README.md · README_KR.md
├── Sources/
│   └── Keynoter/
│       ├── main.swift
│       ├── CLI/                 — REPL, 파싱, 콘솔 출력
│       ├── Session/             — 세션 상태
│       ├── Diagnostics/         — /doctor 점검               (Phase 1)
│       ├── Keynote/             — AppleScript 실행           (Phase 2)
│       ├── Domain/              — 액션, 검증                 (Phase 3)
│       └── AI/                  — Foundation Models 클라이언트 (Phase 4)
└── Tests/
    └── KeynoterTests/           — Swift Testing 스위트
```

아키텍처, 구현 규칙, MVP 범위, 현재 설계 결정 사항은 다음 문서를 참고하세요:

-   [`CLAUDE_KR.md`](./CLAUDE_KR.md) (한국어) / [`CLAUDE.md`](./CLAUDE.md) (영문 원본)
-   [`AGENTS.md`](./AGENTS.md)

## 다음 단계

먼저 Phase 1(`/doctor`, `/status`)을 마무리한 뒤, `/create`와 `/edit`가
AppleScript를 통해 실제 Keynote 문서를 조작하기 시작하는 Phase 2로 넘어갑니다.

그다음이 `PresentationAction` 도메인 계약 정의입니다:

-   액션 타입
-   Foundation Models 구조화 출력
-   검증 규칙
-   AppleScript 매핑
-   undo/redo 동작
-   오류/결과 처리

전체 단계 계획은 [`CLAUDE_KR.md`](./CLAUDE_KR.md)에 있습니다.

------------------------------------------------------------------------

**Keynoter** — Mac에게 말을 걸어 Keynote 프레젠테이션을 만들고 편집하세요.
