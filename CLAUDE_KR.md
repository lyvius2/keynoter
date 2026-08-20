# Keynoter — 개발자 가이드

## 프로젝트

**Keynoter**는 Apple의 온디바이스 Foundation Models를 기반으로, 자연어 대화를 통해
Apple Keynote 프레젠테이션을 생성하고 편집하는 macOS CLI입니다.

```
$ keynoter

Keynoter
On-device AI presentation assistant for Apple Keynote

> /create demo
✓ Created demo.key

> Create an 8-slide presentation about AWS MSK Migration for software engineers.
Planning...
Generating 8 slides...
✓ Done.

> /script
tell application "Keynote" ...
```

---

## 타협 불가 아키텍처 규칙

1. **모델이 생성한 AppleScript를 직접 실행하지 않는다.** 모델은 구조화된
   `PresentationAction` 값을 생성하며, 결정론적(deterministic) Swift 렌더러가 이를
   AppleScript로 변환한다.

2. 파이프라인은 항상 다음과 같아야 한다:
   ```
   User Prompt → FoundationModels → PresentationAction → Validation → AppleScriptRenderer → osascript → Keynote
   ```

3. **슬래시 명령어**는 앱을 제어한다 (`/create`, `/save`, `/undo` 등).
   **자연어**는 프레젠테이션 콘텐츠를 제어한다.

4. `/script`는 실제로 렌더링된 AppleScript를 보여줘야 하며, 모델의 원본 출력을
   그대로 보여줘서는 안 된다.

5. Ollama를 비롯한 외부 추론 서버를 요구하지 않는다.

---

## 기술 스택

| 영역 | 기술 |
|---|---|
| 언어 | Swift 6 |
| 빌드 | Swift Package Manager |
| 플랫폼 | macOS 26+ |
| AI | Apple FoundationModels 프레임워크 (`SystemLanguageModel`, `LanguageModelSession`, `@Generable`) |
| 자동화 | `osascript`를 통한 AppleScript |
| 인터페이스 | 비동기 REPL (stdin/stdout) |

---

## 소스 구조

```
Sources/
└── Keynoter/
    ├── main.swift                      — 비동기 진입점, REPL 실행
    ├── CLI/
    │   ├── REPL.swift                  — read-eval-print 루프
    │   ├── Command.swift               — 슬래시 명령어 enum + 명령어 카탈로그
    │   ├── CommandParser.swift         — 입력 토큰화, Command 또는 자연어 프롬프트 반환
    │   ├── LineReader.swift            — stdin 줄 단위 입력, TTY 감지
    │   └── Console.swift               — 모든 터미널 출력 및 스타일링
    ├── AI/
    │   ├── FoundationModelClient.swift — LanguageModelSession 소유
    │   ├── PresentationPlanner.swift   — 자연어 프롬프트 → [PresentationAction]
    │   └── PromptBuilder.swift         — 시스템 지시문 + 사용자 프롬프트 구성
    ├── Domain/
    │   ├── PresentationSpec.swift      — PresentationSpec, SlideSpec, SlideLayout
    │   ├── PresentationAction.swift    — PresentationAction enum + @Generable 타입 + 검증
    │   └── InverseBuilder.swift        — 액션 → 그 액션을 되돌리는 액션
    ├── Keynote/
    │   ├── KeynoteController.swift     — 문서 생성/열기/저장, 슬라이드 메타데이터 조회
    │   ├── AppleScriptRenderer.swift   — PresentationAction → AppleScript 문자열
    │   ├── AppleScriptString.swift     — AppleScript 리터럴용 단일 이스케이퍼
    │   ├── ActionRunner.swift          — 검증 → 스냅샷 → 렌더 → 실행 → 기록
    │   └── AppleScriptExecutor.swift   — osascript 실행, 결과 또는 오류 반환
    ├── Session/
    │   ├── Session.swift               — 인메모리 세션 상태
    │   └── History.swift               — 액션 로그, undo/redo 스택
    └── Diagnostics/
        └── Doctor.swift                — /doctor 환경 점검

Tests/
└── KeynoterTests/                      — Swift Testing 테스트 스위트, `swift test`로 실행
```

---

## 세션 상태

```swift
// Session이 소유하는 값:
var documentPath: URL?
var mode: SessionMode          // .create | .edit
var isModified: Bool
var slideMetadata: [SlideInfo] // 제목, 인덱스 — 각 액션 후 동기화
var lastAppleScript: String?
var history: History           // HistoryEntry의 undo/redo 스택
```

---

## Undo 모델

`PresentationAction`은 **그 자체로는 되돌릴 수 없다** — `deleteSlide(3)`은 슬라이드 3이
무엇을 담고 있었는지 알지 못한다. 그래서 역액션은 액션을 실행하기 *전에*, 아직 이전 상태를
읽을 수 있을 때 계산하고, 이 쌍을 함께 저장한다:

```swift
struct HistoryEntry {
    let applied: PresentationAction   // /redo에서 다시 실행
    let inverse: PresentationAction   // /undo에서 실행
}
```

전체 순서는 `ActionRunner`가 주도한다:

```
검증 → "이전" 슬라이드 읽기(역액션에 필요할 때만) →
렌더 → 실행 → HistoryEntry 기록
```

undo와 redo는 별도의 메커니즘이 아니다. 같은 렌더러를 통해 액션을 렌더링하고 실행하므로,
되돌린 뒤에도 `/script`는 여전히 의미를 갖는다.

| 액션 | 역액션 | 사전 읽기 필요? |
|---|---|---|
| `addSlide(i, spec)` | `deleteSlide(i)` | 불필요 |
| `deleteSlide(i)` | `addSlide(i, 캡처한 spec)` | **필요** |
| `updateSlide(i, …)` | `updateSlide(i, 이전 값)` | **필요** |
| `moveSlide(a → b)` | `moveSlide(b → a)` | 불필요 |
| `updateSpeakerNotes(i, …)` | `updateSpeakerNotes(i, 이전 노트)` | **필요** |
| `createPresentation` | 없음 — 되돌릴 수 없음 | — |

여기서 따라 나오는 규칙:

- 덱 전체가 아니라 **영향받는 슬라이드 한 장만** 다시 읽는다.
- 역액션이 없는 액션은 **히스토리 전체를 비운다**. 이전 항목들이 기술하던 문서가 더 이상
  존재하지 않으므로, 그 역액션들을 재생하면 지금 열려 있는 문서를 망가뜨린다. 문서를 새로
  열거나 닫을 때 히스토리를 비우는 것도 같은 이유다.
- AppleScript가 실제로 성공하지 않으면 아무것도 기록하지 않는다.
- `deleteSlide`를 되돌리면 `SlideSpec`이 담는 것 — 제목, 본문, 노트 — 이 복원된다. 원래의
  마스터, 이미지, 도형은 복원되지 **않는다**.
- Keynoter는 Keynote 안에서 직접 한 편집을 알 수 없으므로 역액션이 낡을 수 있다. undo는
  현재 슬라이드 수를 기준으로 다시 검증해, 최악의 경우를 AppleScript `-1728` 대신 명확한
  메시지로 바꾼다.

---

## 슬래시 명령어

| 명령어 | 설명 |
|---|---|
| `/help` | 명령어 목록 표시 |
| `/create <name>` | 새 `.key` 문서 생성 후 활성 문서로 설정 |
| `/edit <path>` | 기존 `.key` 문서 열기, 슬라이드 메타데이터 읽기 |
| `/status` | 세션 상태 표시 (문서, 슬라이드, 수정 여부, undo 깊이) |
| `/open` | 활성 문서를 Keynote 전면으로 가져오기 |
| `/save` | 활성 문서 저장 |
| `/save-as <name>` | 새 이름으로 사본 저장 |
| `/undo` | Keynoter가 수행한 마지막 액션 되돌리기 |
| `/redo` | 마지막으로 되돌린 액션 다시 적용 |
| `/script` | 마지막 작업의 AppleScript 출력 |
| `/doctor` | 실행 환경 점검 |
| `/close` | 세션 종료 (REPL은 계속 실행) |
| `/exit` | 종료 (저장되지 않은 변경이 있으면 경고) |

MVP 이후: `/export pdf`, `/export pptx`

---

## 도메인 모델

```swift
// PresentationAction 변형(variants)
enum PresentationAction {
    case createPresentation(title: String, theme: String?)
    case addSlide(index: Int, spec: SlideSpec)
    case updateSlide(index: Int, title: String?, body: [String]?)
    case deleteSlide(index: Int)
    case moveSlide(from: Int, to: Int)
    case updateSpeakerNotes(index: Int, notes: String)
}

// @Generable 래퍼 — 모델이 반환하는 타입
@Generable
struct PresentationPlan {
    var actions: [GenerableAction]
}
```

렌더링 전 검증: 슬라이드 인덱스가 범위 내인지, 텍스트가 길이 제한 이내인지,
텍스트 필드에 AppleScript/셸 메타문자가 없는지 확인한다.

---

## FoundationModels 사용 패턴

```swift
// FoundationModelClient.swift
let session = LanguageModelSession(instructions: systemInstructions)
let plan = try await session.respond(
    to: userPrompt,
    generating: PresentationPlan.self
)
// plan.content.actions → 검증 → 렌더링 → 실행
```

모델이 반환해야 하는 모든 타입에는 `@Generable`을 사용한다. 필드 값을 제약하려면
`@Guide`를 사용한다. 지시문은 3개 문단 이내로 유지한다 (토큰 예산).

---

## AppleScript 렌더러 계약

각 `PresentationAction`은 고정된 AppleScript 템플릿에 매핑된다. 렌더러는 사전에
검증되고 이스케이프된 값만 치환하며, 모델의 원본 출력을 절대 문자열 보간하지 않는다.

```
AddSlide(index: 3, spec: ...) →
  tell application "Keynote"
    set newSlide to make new slide at after slide 2 of document 1
    set object text of default title item of newSlide to "..."
  end tell
```

---

## 빌드 및 실행

**툴체인:** FoundationModels에 필요한 macOS 26 SDK는 Command Line Tools가 아니라
Xcode에만 포함되어 있다. `swift build`가 매니페스트 단계에서 실패하거나
FoundationModels를 찾지 못하면 툴체인을 Xcode로 전환한다:

```bash
sudo xcode-select -s /Applications/Xcode.app
```

관리자 권한이 없다면 명령 앞에 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`를 붙인다.

```bash
# 빌드
swift build

# 실행
swift run keynoter

# 테스트
swift test

# 릴리스 바이너리 빌드
swift build -c release
cp .build/release/keynoter /usr/local/bin/keynoter
```

---

## 테스트

XCTest가 아니라 Swift Testing(`import Testing`, `@Test`, `#expect`)을 사용한다.
테스트는 `Tests/KeynoterTests/`에 두고 `swift test`로 실행한다.

터미널이 아니라 순수 로직을 테스트한다: `CommandParser`, 검증 로직,
그리고 `AppleScriptRenderer`(렌더링된 문자열을 검증하며, 테스트에서 절대 실행하지 않는다).
`Console` 출력과 실제 Keynote 자동화는 테스트 대상에서 제외한다.

가장 가치가 높은 대상은 렌더러다. Phase 3가 완료되면 모든 `PresentationAction`에 대해
텍스트 필드의 따옴표·백슬래시 이스케이프를 포함한 정확한 AppleScript를 고정하는
테스트가 있어야 한다.

---

## 개발 단계

### Phase 1 — CLI 셸 (완료)
`Package.swift` 플랫폼 타깃 · 디렉터리 구조 · `REPL.swift` · `CommandParser.swift`
· `Session.swift` · `Doctor.swift` · `/help` `/doctor` `/status` `/exit`

**완료 기준:** `keynoter`가 실행되고, 슬래시 명령어를 받아들이며, `/doctor`가 동작한다.

### Phase 2 — Keynote 연동 (완료)
`AppleScriptExecutor` · `KeynoteController` · `/create` `/edit` `/open` `/save` `/save-as` `/close`

**완료 기준:** `/create demo`가 `demo.key`를 생성하고, `/status`가 슬라이드 수를 표시한다.

### Phase 3 — 도메인 모델 및 렌더러 (완료)
`PresentationSpec` · `PresentationAction` · `ValidationEngine` · `AppleScriptRenderer`
· `History` · `InverseBuilder` · `ActionRunner` · `/undo` `/redo` `/script`

**완료 기준:** 액션을 적용하고, AppleScript로 렌더링하고, 되돌릴 수 있다.

### Phase 4 — AI 통합 (현재 단계)
`FoundationModelClient` · `PresentationPlanner` · `@Generable` 액션 타입
· REPL의 자연어 입력을 플래너에 연결

**완료 기준:** 자연어 요청을 입력하면 Keynote에서 슬라이드가 엔드투엔드로 생성/편집된다.

**주의:** Keynote 테마 이름은 지역화되어 있다. 한국어 환경에서 `theme "White"`는 `-1728`로
실패하고 `theme "흰색"`이 성공한다. 모델이 제시한 영문 테마 이름을 설치된 테마로 매핑하는
일은 렌더러가 아니라 이 단계의 몫이다.

### Phase 5 — 다듬기
진행 상황 표시 · Apple Intelligence를 사용할 수 없을 때의 우아한 성능 저하(graceful degradation)
· `/exit` 시 미저장 변경 경고 · 컨텍스트 윈도우 관리

### Phase 6 — MVP 이후
`/export pdf` · `/export pptx` · 테마 · 발표자 노트 · 더 다양한 레이아웃

---

## 안전 점검 목록 (실행 전 확인)

- [ ] 슬라이드 인덱스가 현재 슬라이드 수 범위 내인가
- [ ] 텍스트 필드에 AppleScript 메타문자(`"`, `\`, `&`)가 없는가
- [ ] 파일 경로가 허용된 디렉터리 안에 있고 `.key` 확장자를 가지는가
- [ ] 액션 타입이 지원되는 허용 목록(allow-list)에 있는가
- [ ] AppleScript가 Keynote만 대상으로 하는가 — 셸이나 시스템 호출 없음
