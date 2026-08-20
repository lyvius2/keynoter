# Keynoter

[![Platform](https://img.shields.io/badge/platform-macOS%2026%2B-000000?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](https://swift.org)
[![SwiftPM](https://img.shields.io/badge/SwiftPM-compatible-4BC51D?logo=swift&logoColor=white)](https://www.swift.org/documentation/package-manager/)
[![Foundation Models](https://img.shields.io/badge/AI-Foundation%20Models-5E5CE6?logo=apple&logoColor=white)](https://developer.apple.com/documentation/foundationmodels)
![Inference](https://img.shields.io/badge/inference-on--device-blue)
![Status](https://img.shields.io/badge/status-early%20development-orange)

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

> 카프카 마이그레이션을 주제로 5장짜리 발표 자료를 만들어 주세요.
  개발자 대상입니다.

Planning...
Applying 5 changes...
  add slide 1
  add slide 2
  add slide 3
  add slide 4
  update slide 5

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
| `/save-as {filename}` | 사본을 쓰고 그 사본을 계속 편집 |
| `/undo` | 마지막 Keynoter 작업 되돌리기 |
| `/redo` | 마지막으로 되돌린 작업 다시 적용 |
| `/script` | 마지막 작업에서 생성된 AppleScript 표시 |
| `/doctor` | 로컬 Keynoter 환경 점검 |
| `/close` | 활성 문서 세션 닫기 |
| `/exit` | Keynoter 종료 (저장되지 않은 변경이 있으면 한 번 되묻습니다) |

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

## 계획 세우기

평범한 말로 입력한 것은 *계획*이 됩니다. "3번에 슬라이드 추가", "4번 본문 교체"
같은 변경들의 순서 있는 목록입니다. Apple의 온디바이스 모델이 이 계획을 채우며,
AppleScript는 쓰지 않습니다. 애초에 그렇게 요청하지도 않습니다.

덱 하나를 통째로 계획하는 데는 1분 가까이 걸리므로, 계획이 쓰이는 과정을 그대로
보게 됩니다. `Planning...` 아래 줄이 각 단계가 만들어질 때마다 다시 쓰입니다:

``` text
> Apache Kafka를 개발자에게 소개하는 4장짜리 자료를 만들어 주세요.

Planning...
  3. add slide 3 "Key Features" (5 bullets)
```

각 변경은 현재 문서 상태를 기준으로 검사되고, 고정된 AppleScript 템플릿으로
렌더링된 뒤 적용됩니다. 적용되는 대로 한 줄씩 기록됩니다:

``` text
> 4번 슬라이드에 글이 너무 많습니다. 가장 중요한 세 가지만 남겨 주세요.

Planning...
Applying 1 change...
  update slide 4
✓ Done.
```

도중에 실패하면 계획은 거기서 멈춥니다. 밀고 나가지 않습니다 — 뒤의 변경들은
이미 어긋나 버린 슬라이드 번호를 전제로 세워졌기 때문입니다. 그때까지 적용된
것들은 undo 스택에 남습니다.

계획 수립은 전적으로 여러분의 Mac 안에서 이뤄집니다. 발표 자료의 어떤 내용도
기기 밖으로 나가지 않습니다.

## 어느 문서를 다루는가

Keynoter는 "맨 앞에 있는 창"이 아니라, 여러분이 연 문서를 Keynote가 부여한 id로
지목합니다. Keynote에서 다른 덱을 열거나 이리저리 클릭해도, 어제 만든 발표 자료를
화면에 띄워 두어도, `/save`와 `/undo`를 비롯한 모든 슬라이드 편집은 세션이 붙잡고
있는 문서에만 적용됩니다.

그 문서를 Keynote에서 닫아 버리면, 다음 명령은 대신 들어온 다른 문서를 조용히
편집하는 대신 그 사실을 알려 줍니다.

## 되돌리기 (Undo)

구조화된 액션은 스스로를 되돌릴 수 없습니다 — `슬라이드 3 삭제`는 슬라이드 3이
무엇을 담고 있었는지 알지 못합니다. 그래서 Keynoter는 액션을 실행하기 전, 아직
이전 상태를 읽을 수 있을 때 바꾸려는 슬라이드 한 장을 읽어 두고 그것을 되돌리는
액션을 만듭니다. 둘은 함께 저장됩니다:

``` text
delete slide 3   ← 요청한 것          (/redo가 다시 실행)
add slide 3 …    ← 되돌리는 것        (/undo가 실행)
```

따라서 되돌리기 역시 같은 렌더러를 거치는 하나의 액션일 뿐이며, 되돌린 뒤에도
`/script`가 의미 있는 결과를 보여주는 이유가 여기에 있습니다.

알아 둘 만한 두 가지 한계가 있습니다. 삭제를 되돌리면 슬라이드의 제목, 본문,
노트는 복원되지만 마스터, 이미지, 도형은 복원되지 않습니다. 또한 Keynoter는
Keynote에서 직접 한 편집을 알 수 없으므로, 양쪽을 오가며 작업하면 되돌리기가
낡을 수 있습니다.

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

Keynoter는 **초기 개발 단계**에 있지만, 파이프라인 전체가 이제 끝에서 끝까지
동작합니다. 슬래시 명령어는 REPL에서 파싱되고 디스패치되며, `/doctor`는 로컬
실행 환경을 점검하고, Keynote를 조작하는 여섯 개의 명령어
(`/create`, `/edit`, `/open`, `/save`, `/save-as`, `/close`)는 AppleScript로
Keynote와 통신합니다. `/status`는 세션이 붙잡은 문서에서 슬라이드 메타데이터를
실시간으로 읽어 옵니다.

평범한 말로 요청을 입력하면 Apple의 온디바이스 모델이 변경 계획을 세우고,
검증된 `PresentationAction`으로 옮긴 뒤, 각각을 고정된 AppleScript 템플릿으로
렌더링해 순서대로 적용합니다. `/undo`, `/redo`, `/script`가 그 결과에 연결되어
있습니다. 모델이 계획을 쓰는 과정도 그대로 보여 줍니다. 남은 것은
다듬기입니다 — 긴 세션을 위한 컨텍스트 윈도우 관리, 그리고 내보내기.

구현 마일스톤:

-   [x] 대화형 CLI / REPL — 명령어 파싱, 디스패치, 세션 상태
-   [x] 환경 진단 (`/doctor`, `/status`)
-   [x] Keynote 문서 생성 및 편집
-   [x] 저장/열기/세션 관리
-   [x] 구조화된 `PresentationAction` 생성 및 검증
-   [x] 결정론적 AppleScript 렌더링
-   [x] undo/redo
-   [x] AppleScript 확인 (`/script`)
-   [x] 전면 창과 무관하게 id로 문서 지목
-   [x] Foundation Models 통합 — 자연어에서 슬라이드까지

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
│       ├── Session/             — 세션 상태, undo/redo 히스토리
│       ├── Diagnostics/         — /doctor 점검
│       ├── Keynote/             — AppleScript 렌더링 및 실행
│       ├── Domain/              — 액션, 검증, 역액션
│       └── AI/                  — Foundation Models 클라이언트 (Phase 4)
└── Tests/
    └── KeynoterTests/           — Swift Testing 스위트
```

아키텍처, 구현 규칙, MVP 범위, 현재 설계 결정 사항은 다음 문서를 참고하세요:

-   [`CLAUDE_KR.md`](./CLAUDE_KR.md) (한국어) / [`CLAUDE.md`](./CLAUDE.md) (영문 원본)
-   [`AGENTS.md`](./AGENTS.md)

## 다음 단계

Phase 5 — 다듬기:

-   Apple Intelligence를 사용할 수 없을 때의 우아한 동작
-   긴 세션을 위한 컨텍스트 윈도우 관리

전체 단계 계획은 [`CLAUDE_KR.md`](./CLAUDE_KR.md)에 있습니다.

------------------------------------------------------------------------

**Keynoter** — Mac에게 말을 걸어 Keynote 프레젠테이션을 만들고 편집하세요.
