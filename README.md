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

> Create a 5-slide presentation about AWS MSK migration for software
  engineers. Cover AS-IS, TO-BE, and migration strategy.

Planning...
Applying 5 changes...
  add slide 1
  add slide 2
  add slide 3
  add slide 4
  update slide 5

✓ Done.
```

## Get Started

**What you need**

-   macOS 26 or later
-   Xcode 26 --- the macOS 26 SDK it ships with is what provides the
    FoundationModels framework. The Command Line Tools alone cannot build this
    package.
-   Apple Intelligence turned on (System Settings > Apple Intelligence & Siri)
-   Keynote installed

**Build**

``` bash
git clone https://github.com/lyvius2/keynoter.git
cd keynoter

# Point the toolchain at Xcode if `xcode-select -p` says CommandLineTools
sudo xcode-select -s /Applications/Xcode.app

swift build -c release
```

Without the toolchain switch, the build stops at the manifest with
`error: 'keynoter': Invalid manifest` and undefined `PackageDescription`
symbols. If you would rather not change the system-wide setting --- or have no
admin rights --- prefix the command instead:

``` bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build -c release
```

**Run**

``` bash
swift run keynoter                              # from the source directory
```

Or put the binary on your `PATH` and run it from anywhere:

``` bash
sudo cp .build/release/keynoter /usr/local/bin/keynoter
keynoter
```

**First run**

Start with `/doctor`. It checks the five things Keynoter needs and says which
one is missing:

``` text
$ keynoter

> /doctor
Doctor
✓ macOS: 26.5.1
✓ Xcode toolchain: /Applications/Xcode.app/Contents/Developer
✓ Keynote: /Applications/Keynote.app
✓ Apple Intelligence: SystemLanguageModel available
✓ Keynote automation: granted

Environment ready.
```

The first command that touches Keynote raises the macOS Automation prompt ---
allow it, or every Keynote command fails with a permission error until you do
(System Settings > Privacy & Security > Automation). The Xcode toolchain check
is about *building*: a binary you already built runs whether or not
`xcode-select` still points at Xcode.

Then make something:

``` text
> /create demo
✓ Created demo.key

> Create a 4-slide overview of Apache Kafka for engineers.
Planning...
Applying 4 changes...
  add slide 1
  add slide 2
  add slide 3
  update slide 4
✓ Done.

> /save
✓ Saved demo.key
```

`demo.key` lands in the directory you started `keynoter` from; `/create` and
`/edit` also take absolute paths and `~`. `/help` lists every command, `/script`
shows the AppleScript that was actually run, and `/undo` walks the last change
back.


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
| `/save-as {filename}` | Write a copy and continue editing it |
| `/export pdf \| pptx [{path}]` | Export the deck as PDF or PowerPoint |
| `/undo` | Undo the latest Keynoter operation |
| `/redo` | Reapply the latest undone operation |
| `/script` | Show the AppleScript generated for the latest operation |
| `/doctor` | Check the local Keynoter environment |
| `/close` | Close the active document session |
| `/exit` | Exit Keynoter (asks again when there are unsaved changes) |

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

## Planning

What you type in plain language becomes a *plan*: an ordered list of changes
like "add a slide at 3" or "replace slide 4's bullets". Apple's on-device model
fills that plan in; it never writes AppleScript, and it is never asked to.

A plan for a whole deck takes the better part of a minute to write, so you watch
it being written --- the line under `Planning...` is rewritten as each step takes
shape:

``` text
> Create a 4-slide overview of Apache Kafka for engineers.

Planning...
  3. add slide 3 "Key Features" (5 bullets)
```

Each change is then checked against the document as it stands, rendered to a
fixed AppleScript template, and applied. Every step is logged as it lands:

``` text
> Slide 4 has too much text. Keep only the three most important points.

Planning...
Applying 1 change...
  update slide 4
✓ Done.
```

If a step fails, the plan stops there rather than pressing on --- the later
changes were planned around slide numbers that no longer hold. Whatever already
applied stays on the undo stack.

Planning runs entirely on your Mac. Nothing about your presentation leaves it.

## Which Document?

Keynoter targets the document you opened, by the id Keynote assigns it --- not
"whatever window is in front". You can click around in Keynote, open other
decks, or leave a presentation from yesterday on screen, and `/save`, `/undo`
and every slide edit still land on your session's document.

If you close that document inside Keynote, the next command says so instead of
quietly editing whatever took its place.

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

Keynoter is in **early development**, but the whole pipeline now runs
end to end. Slash commands parse and dispatch through the REPL, `/doctor`
reports on the local environment, and the seven Keynote-driving commands
(`/create`, `/edit`, `/open`, `/save`, `/save-as`, `/export`, `/close`)
talk to Keynote through AppleScript. `/status` reads live slide metadata back from
the session's document.

Typing a request in plain language plans a set of changes with Apple's
on-device model, converts them to validated `PresentationAction`s, renders
each to a fixed AppleScript template, and applies them in order --- with
`/undo`, `/redo`, and `/script` wired to the result, and the plan shown
taking shape while the model writes it.

Implementation milestones:

-   [x] interactive CLI / REPL --- command parsing, dispatch, session state
-   [x] environment diagnostics (`/doctor`, `/status`)
-   [x] Keynote document creation and editing
-   [x] save/open/session management
-   [x] structured `PresentationAction` generation and validation
-   [x] deterministic AppleScript rendering
-   [x] undo/redo
-   [x] AppleScript inspection (`/script`)
-   [x] document targeting by id, independent of the front window
-   [x] Foundation Models integration --- natural language to slides
-   [x] context-window management --- proactive session reset with user notification
-   [x] PDF and PowerPoint export (`/export pdf`, `/export pptx`)

Richer slide layouts (hero, comparison, metric, …), master slide selection,
theme awareness, slide transitions, and slide-based animation alternatives are
planned for the rest of Phase 6. Keynote's native object builds are not
scriptable, but staged slides and Magic Move are feasible; they are not yet
implemented in Keynoter.

## Development

``` bash
swift build          # build
swift run keynoter   # run the REPL
swift test           # run the test suite
```

The toolchain requirement is the same one [Get Started](#get-started) covers:
`swift build` fails while compiling the manifest when the active toolchain is
the Command Line Tools rather than Xcode.

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

Phase 6 --- richer presentations:

-   **6a** ✅ Keynote AppleScript capability audit --- results in
    [`CAPABILITIES.md`](./CAPABILITIES.md)
-   **6b** ✅ `/export pdf` and `/export pptx`
-   **6c** `LayoutIntent` replacing `SlideLayout` --- hero, comparison, metric,
    section, and more; master slide selection by index
-   **6d** Theme awareness --- locale-safe runtime matching instead of
    model-generated theme names
-   **6e** Tool calling architecture (experimental, after 6c/6d are stable)
-   **6f** Transitions and animation alternatives --- staged slides and Magic
    Move; native Build In/Out/Action effects are not scriptable

The full phase plan and architectural decisions live in
[`CLAUDE.md`](./CLAUDE.md).

------------------------------------------------------------------------

**Keynoter** --- Create and edit Keynote presentations by talking to
your Mac.
