# Keynoter

[![Platform](https://img.shields.io/badge/platform-macOS%2026%2B-000000?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](https://swift.org)
[![SwiftPM](https://img.shields.io/badge/SwiftPM-compatible-4BC51D?logo=swift&logoColor=white)](https://www.swift.org/documentation/package-manager/)
[![Foundation Models](https://img.shields.io/badge/AI-Foundation%20Models-5E5CE6?logo=apple&logoColor=white)](https://developer.apple.com/documentation/foundationmodels)
![Inference](https://img.shields.io/badge/inference-on--device-blue)
![Status](https://img.shields.io/badge/status-early%20development-orange)

> [한국어(Korean) 문서](./README_KR.md)

**An on-device AI presentation agent for Apple Keynote.**

Keynoter is a macOS-native conversational CLI that creates and edits
Apple Keynote presentations using Apple's on-device Foundation Models.

Instead of manually manipulating every slide, you work with Keynoter
through natural language:

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

## Concept

Keynoter combines an agent-style CLI with native macOS automation:

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

The language model decides **what should change**.

Keynoter's Swift runtime decides **how the change is safely applied to
Keynote**.

## Why Keynoter?

Keynote is inherently a macOS application, which makes Apple's on-device
model a natural fit for an AI presentation workflow.

Keynoter is designed around:

-   Apple Foundation Models / Apple Intelligence
-   on-device inference
-   Swift
-   AppleScript / Apple Events
-   Apple Keynote
-   a conversational, agentic CLI experience

The primary workflow does not require Ollama or an external inference
server.

## CLI

Planned MVP commands:

| Command | Description |
|---|---|
| `/help` | Show available commands |
| `/create {filename}` | Create a new Keynote presentation |
| `/edit {path}` | Start editing an existing Keynote presentation |
| `/status` | Show the current session and document state |
| `/open` | Open or focus the active document in Keynote |
| `/save` | Save the active presentation |
| `/save-as {filename}` | Save the presentation under another name |
| `/undo` | Undo the latest Keynoter operation |
| `/redo` | Reapply the latest undone operation |
| `/script` | Show the AppleScript generated for the latest operation |
| `/doctor` | Check the local Keynoter environment |
| `/close` | Close the active document session |
| `/exit` | Exit Keynoter |

Presentation changes themselves are expressed in natural language rather
than as commands:

``` text
> Add a TO-BE Architecture slide after slide 3.

> Slide 4 has too much text. Keep only the three most important points.

> Delete slide 5.

> Rewrite the presentation for an executive audience.
```

## Safety by Design

Keynoter does **not** normally ask the language model to generate
arbitrary AppleScript and execute it directly.

The intended pipeline is:

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

This keeps model reasoning separate from application execution and makes
generated automation inspectable through `/script`.

## Undo

A structured action cannot reverse itself --- `delete slide 3` does not
carry what slide 3 held. So before an action runs, while the old state is
still readable, Keynoter reads back the one slide it is about to change
and builds the action that puts it back. Both are stored together:

``` text
delete slide 3   ← what you asked for      (replayed by /redo)
add slide 3 …    ← what puts it back       (replayed by /undo)
```

Undo is therefore just another action through the same renderer, which is
why `/script` still shows you something meaningful after one.

Two limits worth knowing: undoing a deletion restores the slide's title,
body and notes but not its master, images or shapes; and Keynoter cannot
see edits you make directly inside Keynote, so undo can go stale if you
work in both places at once.

## Technology

-   **Platform:** macOS
-   **Language:** Swift
-   **Build:** Swift Package Manager
-   **AI:** Apple Foundation Models framework
-   **Presentation:** Apple Keynote
-   **Automation:** AppleScript / Apple Events
-   **Interface:** Interactive CLI / REPL

Xcode is required: the macOS 26 SDK it ships with is what provides the
FoundationModels framework, and the Command Line Tools alone are not
enough to build the package. It does not need to be your primary editor.

## Project Status

Keynoter is in **early development**, and everything below the language
model is now in place. Slash commands parse and dispatch through the REPL,
`/doctor` reports on the local environment, and the six Keynote-driving
commands (`/create`, `/edit`, `/open`, `/save`, `/save-as`, `/close`) talk
to Keynote through AppleScript. `/status` reads live slide metadata back
from the front document.

The action pipeline is complete: every `PresentationAction` is validated,
rendered to a fixed AppleScript template, executed, and recorded on an
undo stack, with `/undo`, `/redo`, and `/script` wired to it. What remains
is the Foundation Models plumbing that turns natural-language input into
those actions.

Implementation milestones:

-   [x] interactive CLI / REPL --- command parsing, dispatch, session state
-   [x] environment diagnostics (`/doctor`, `/status`)
-   [x] Keynote document creation and editing
-   [x] save/open/session management
-   [x] structured `PresentationAction` generation and validation
-   [x] deterministic AppleScript rendering
-   [x] undo/redo
-   [x] AppleScript inspection (`/script`)
-   [ ] Foundation Models integration

PDF and PowerPoint export, richer layouts, diagrams, images, themes, and
presentation templates are planned for later phases.

## Development

``` bash
swift build          # build
swift run keynoter   # run the REPL
swift test           # run the test suite
```

If `swift build` fails while compiling the manifest, the active toolchain
is the Command Line Tools rather than Xcode. Point it at Xcode once:

``` bash
sudo xcode-select -s /Applications/Xcode.app
```

Package layout --- directories tagged with a phase do not exist yet:

``` text
keynoter/
├── Package.swift
├── CLAUDE.md · CLAUDE_KR.md     — developer guide
├── AGENTS.md
├── README.md · README_KR.md
├── Sources/
│   └── Keynoter/
│       ├── main.swift
│       ├── CLI/                 — REPL, parsing, console output
│       ├── Session/             — session state, undo/redo history
│       ├── Diagnostics/         — /doctor checks
│       ├── Keynote/             — AppleScript rendering and execution
│       ├── Domain/              — actions, validation, inverses
│       └── AI/                  — Foundation Models client    (Phase 4)
└── Tests/
    └── KeynoterTests/           — Swift Testing suites
```

For architecture, implementation rules, MVP scope, and current design
decisions, read:

-   [`CLAUDE.md`](./CLAUDE.md) (한국어: [`CLAUDE_KR.md`](./CLAUDE_KR.md))
-   [`AGENTS.md`](./AGENTS.md)

## Planned Next Step

Phase 4 --- Foundation Models integration:

-   a `LanguageModelSession` producing `@Generable` action types;
-   a planner that turns one natural-language request into a sequence of
    validated `PresentationAction`s;
-   natural-language input wired into the REPL;
-   mapping model-supplied theme names onto the locally installed
    (and localized) Keynote themes.

The full phase plan lives in [`CLAUDE.md`](./CLAUDE.md).

------------------------------------------------------------------------

**Keynoter** --- Create and edit Keynote presentations by talking to
your Mac.
