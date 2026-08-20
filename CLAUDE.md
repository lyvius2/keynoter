# Keynoter — Developer Guide

## Project

**Keynoter** is a macOS CLI for creating and editing Apple Keynote presentations through
natural-language conversation, powered by Apple's on-device Foundation Models.

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

## Non-Negotiable Architecture Rules

1. **Never execute model-generated AppleScript directly.** The model produces structured
   `PresentationAction` values. A deterministic Swift renderer converts those to AppleScript.

2. The required pipeline is always:
   ```
   User Prompt → FoundationModels → PresentationAction → Validation → AppleScriptRenderer → osascript → Keynote
   ```

3. **Slash commands** control the app (`/create`, `/save`, `/undo`, etc.).
   **Natural language** controls the presentation content.

4. `/script` must show the actual rendered AppleScript, never raw model output.

5. Do not require Ollama or any external inference server.

---

## Technology Stack

| Area | Technology |
|---|---|
| Language | Swift 6 |
| Build | Swift Package Manager |
| Platform | macOS 26+ |
| AI | Apple FoundationModels framework (`SystemLanguageModel`, `LanguageModelSession`, `@Generable`) |
| Automation | AppleScript via `osascript` |
| Interface | Async REPL (stdin/stdout) |

---

## Source Layout

```
Sources/
└── Keynoter/
    ├── main.swift                      — async entry point, launches REPL
    ├── CLI/
    │   ├── REPL.swift                  — read-eval-print loop
    │   ├── Command.swift               — slash command enum + command catalog
    │   ├── CommandParser.swift         — tokenizes input, returns Command or NL prompt
    │   ├── LineReader.swift            — stdin line input, TTY detection
    │   └── Console.swift               — all terminal output and styling
    ├── AI/
    │   ├── FoundationModelClient.swift — owns LanguageModelSession
    │   ├── PresentationPlanner.swift   — NL prompt → [PresentationAction]
    │   └── PromptBuilder.swift         — builds system instructions + user prompt
    ├── Domain/
    │   ├── PresentationSpec.swift      — PresentationSpec, SlideSpec, SlideLayout
    │   ├── PresentationAction.swift    — PresentationAction enum + @Generable types + validation
    │   └── InverseBuilder.swift        — action → the action that reverses it
    ├── Keynote/
    │   ├── KeynoteController.swift     — create/open/save document, read slide metadata
    │   ├── AppleScriptRenderer.swift   — PresentationAction → AppleScript string
    │   ├── AppleScriptString.swift     — the one escaper for AppleScript literals
    │   ├── ActionRunner.swift          — validate → snapshot → render → execute → record
    │   └── AppleScriptExecutor.swift   — runs osascript, returns result or error
    ├── Session/
    │   ├── Session.swift               — in-memory session state
    │   └── History.swift               — action log, undo/redo stacks
    └── Diagnostics/
        └── Doctor.swift                — /doctor environment checks

Tests/
└── KeynoterTests/                      — Swift Testing suites, run with `swift test`
```

---

## Session State

```swift
// Session owns:
var documentPath: URL?
var mode: SessionMode          // .create | .edit
var isModified: Bool
var slideMetadata: [SlideInfo] // title, index — synced after each action
var lastAppleScript: String?
var history: History           // undo/redo stacks of HistoryEntry
```

---

## Undo Model

A `PresentationAction` is **not invertible on its own** — `deleteSlide(3)` does
not carry what slide 3 held. So the inverse is computed *before* the action runs,
while the old state is still readable, and the pair is what gets stored:

```swift
struct HistoryEntry {
    let applied: PresentationAction   // re-run on /redo
    let inverse: PresentationAction   // run on /undo
}
```

`ActionRunner` drives the whole sequence:

```
validate → read the "before" slide (only if the inverse needs it) →
render → execute → record HistoryEntry
```

Undo and redo are not a separate mechanism: they render and execute an action
through the same renderer, so `/script` stays meaningful afterwards.

| Action | Inverse | Needs a pre-read? |
|---|---|---|
| `addSlide(i, spec)` | `deleteSlide(i)` | no |
| `deleteSlide(i)` | `addSlide(i, captured spec)` | **yes** |
| `updateSlide(i, …)` | `updateSlide(i, old values)` | **yes** |
| `moveSlide(a → b)` | `moveSlide(b → a)` | no |
| `updateSpeakerNotes(i, …)` | `updateSpeakerNotes(i, old notes)` | **yes** |
| `createPresentation` | none — irreversible | — |

Rules that follow from this:

- Only the **one affected slide** is read back, never the whole deck.
- An action with no inverse **clears the entire history**: the document the
  earlier entries described is gone, so replaying their inverses would corrupt
  whatever is open now. Attaching or closing a document clears it for the same
  reason.
- Nothing is recorded unless the AppleScript actually succeeded.
- Undoing a `deleteSlide` restores title, body and notes — everything `SlideSpec`
  carries. The original master, images and shapes are **not** recovered.
- Keynoter cannot see edits made directly inside Keynote, so a stale inverse is
  possible. Undo re-validates against the current slide count to turn the worst
  cases into a clear message instead of an AppleScript `-1728`.

---

## Slash Commands

| Command | Description |
|---|---|
| `/help` | List commands |
| `/create <name>` | Create new `.key` document, set as active |
| `/edit <path>` | Open existing `.key` document, read slide metadata |
| `/status` | Show session state (document, slides, modified, undo depth) |
| `/open` | Bring active document to foreground in Keynote |
| `/save` | Save active document |
| `/save-as <name>` | Save copy under new name |
| `/undo` | Revert last Keynoter-driven action |
| `/redo` | Reapply last undone action |
| `/script` | Print AppleScript from last operation |
| `/doctor` | Check runtime environment |
| `/close` | Close session, keep REPL running |
| `/exit` | Quit (warn if unsaved changes) |

Post-MVP: `/export pdf`, `/export pptx`

---

## Domain Model

```swift
// PresentationAction variants
enum PresentationAction {
    case createPresentation(title: String, theme: String?)
    case addSlide(index: Int, spec: SlideSpec)
    case updateSlide(index: Int, title: String?, body: [String]?)
    case deleteSlide(index: Int)
    case moveSlide(from: Int, to: Int)
    case updateSpeakerNotes(index: Int, notes: String)
}

// @Generable wrapper — what the model returns
@Generable
struct PresentationPlan {
    var actions: [GenerableAction]
}
```

Validation before rendering: slide index in bounds, text within length limits,
no AppleScript/shell metacharacters in text fields.

---

## FoundationModels Usage Pattern

```swift
// FoundationModelClient.swift
let session = LanguageModelSession(instructions: systemInstructions)
let plan = try await session.respond(
    to: userPrompt,
    generating: PresentationPlan.self
)
// plan.content.actions → validate → render → execute
```

Use `@Generable` on all types the model must return. Use `@Guide` to constrain
field values. Keep instructions under 3 paragraphs (token budget).

---

## AppleScript Renderer Contract

Each `PresentationAction` maps to a fixed AppleScript template. The renderer
substitutes only pre-validated, escaped values. It never interpolates raw model output.

```
AddSlide(index: 3, spec: ...) →
  tell application "Keynote"
    set newSlide to make new slide at after slide 2 of document 1
    set object text of default title item of newSlide to "..."
  end tell
```

---

## Build & Run

**Toolchain:** the macOS 26 SDK (required for FoundationModels) ships only with Xcode,
not the Command Line Tools. If `swift build` fails on the manifest or cannot find
FoundationModels, point the toolchain at Xcode:

```bash
sudo xcode-select -s /Applications/Xcode.app
```

Without admin rights, prefix commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` instead.

```bash
# Build
swift build

# Run
swift run keynoter

# Test
swift test

# Build release binary
swift build -c release
cp .build/release/keynoter /usr/local/bin/keynoter
```

---

## Testing

Swift Testing (`import Testing`, `@Test`, `#expect`) — not XCTest. Tests live in
`Tests/KeynoterTests/` and run with `swift test`.

Test the pure logic, not the terminal: `CommandParser`, validation, and the
`AppleScriptRenderer` (assert on the rendered string — never execute it in a test).
`Console` output and live Keynote automation stay out of the suite.

The renderer is the highest-value target: once Phase 3 lands, every
`PresentationAction` should have a test pinning its exact AppleScript, including
escaping of quotes and backslashes in text fields.

---

## Development Phases

### Phase 1 — CLI Shell (done)
`Package.swift` platform target · directory structure · `REPL.swift` · `CommandParser.swift`
· `Session.swift` · `Doctor.swift` · `/help` `/doctor` `/status` `/exit`

**Done when:** `keynoter` launches, accepts slash commands, `/doctor` runs.

### Phase 2 — Keynote Integration (done)
`AppleScriptExecutor` · `KeynoteController` · `/create` `/edit` `/open` `/save` `/save-as` `/close`

**Done when:** `/create demo` produces `demo.key`, `/status` shows slide count.

### Phase 3 — Domain Model & Renderer (done)
`PresentationSpec` · `PresentationAction` · `ValidationEngine` · `AppleScriptRenderer`
· `History` · `InverseBuilder` · `ActionRunner` · `/undo` `/redo` `/script`

**Done when:** Actions can be applied, rendered to AppleScript, and undone.

### Phase 4 — AI Integration (current)
`FoundationModelClient` · `PresentationPlanner` · `@Generable` action types
· Natural-language input wired to planner in REPL

**Done when:** Typing a NL request creates/edits slides in Keynote end-to-end.

**Watch out:** Keynote theme names are localized. On a Korean system
`theme "White"` fails with `-1728` and `theme "흰색"` succeeds. Mapping a
model-supplied English theme name onto the installed themes belongs here, not in
the renderer.

### Phase 5 — Polish
Progress display · graceful degradation when Apple Intelligence unavailable
· unsaved-change warning on `/exit` · context window management

### Phase 6 — Post-MVP
`/export pdf` · `/export pptx` · themes · speaker notes · richer layouts

---

## Safety Checklist (before any execution)

- [ ] Slide index is within current slide count
- [ ] Text fields are free of AppleScript metacharacters (`"`, `\`, `&`)
- [ ] File path is within allowed directories and has `.key` extension
- [ ] Action type is in the supported allow-list
- [ ] AppleScript targets Keynote only — no shell or system calls
