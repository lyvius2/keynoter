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
    │   ├── PresentationPlan.swift      — @Generable plan types, streaming progress, conversion to actions
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
var documentRef: DocumentRef?  // which Keynote document, by id
var mode: SessionMode          // .create | .edit
var isModified: Bool
var slideMetadata: [SlideInfo] // title, index — synced after each action
var lastAppleScript: String?
var history: History           // undo/redo stacks of HistoryEntry
```

---

## Document Targeting

**Never `front document` or `document 1`.** Those mean "whichever window the
user last clicked", so bringing another deck forward in Keynote silently
redirects every Keynoter command at it.

Keynote gives each open document a UUID. `/create` and `/edit` capture it, the
session holds it, and every script names it:

```
tell application "Keynote"
    delete slide 3 of document id "C29AB346-…"
end tell
```

Consequences worth keeping:

- The id survives saving and window reordering, and disambiguates two open
  documents that share a file name.
- If the user closes the document in Keynote, the next command fails with
  `-1728` instead of hitting the wrong deck. Failing loudly is the point.
- Keynote offers no way to raise one document's window (`set index of window`
  fails with `-10006`), so `/open` re-opens the file the document is already
  showing — that brings it forward without opening a second copy.
- `save … in <file>` writes a *copy* and leaves the open document bound to its
  old file. `/save-as` therefore closes the original and opens the copy, so
  later `/save` calls cannot write to the previous path.

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
| `/save-as <name>` | Write a copy, then continue editing it (original is closed) |
| `/undo` | Revert last Keynoter-driven action |
| `/redo` | Reapply last undone action |
| `/script` | Print AppleScript from last operation |
| `/doctor` | Check runtime environment |
| `/close` | Close session, keep REPL running |
| `/exit` | Quit (warn if unsaved changes) |

Post-MVP: `/export pdf`, `/export pptx`

### Quitting with unsaved changes

`/exit` refuses **once** when Keynoter has applied actions that were never
saved, and goes through on the repeat:

```
> /exit
! demo.key has unsaved changes. /save first, or /exit again to quit anyway.
> /exit
! demo.key has unsaved changes; it is still open in Keynote.
Goodbye.
```

- The refusal is a message, not a blocking `save first? [y/n]` question. Such a
  question reads the next line of input, which silently swallows a command when
  Keynoter is driven by a piped script. One input line stays one decision.
- **Exactly one refusal**, whatever the state of the session — no answer, no
  failure and no open document can trap the user inside the REPL.
- Any other input clears the pending confirmation, so a warning printed three
  commands ago never counts as the answer to this `/exit`.
- Ctrl-D is the same quit request and gets the same guard, but **only at a
  terminal**: at the end of a piped script there is no second Ctrl-D to give,
  and waiting for one would hang the loop.
- Keynoter never closes the document on the way out, so unsaved work is sitting
  in Keynote, not lost. The parting line says so — it prints on every exit that
  leaves changes behind, including Ctrl-D and end-of-pipe.

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
let responses = session.streamResponse(
    to: userPrompt,
    generating: PresentationPlan.self,
    options: .init(sampling: .greedy)
)
var latest: GeneratedContent?
for try await snapshot in responses {
    latest = snapshot.rawContent          // the complete answer, once the loop ends
    onProgress(PlanProgress(snapshot.content))
}
let plan = try PresentationPlan(latest!)  // → validate → render → execute
```

Use `@Generable` on all types the model must return. Use `@Guide` to constrain
field values. Keep instructions under 3 paragraphs (token budget).

Decisions that hold the planner together:

- **`.greedy` sampling.** A plan is a structured command, not creative writing:
  the same request against the same deck should produce the same slides, and a
  misbehaving prompt has to be reproducible.
- **`GenerableAction` is a flat record**, not an enum with associated values —
  easier for a small on-device model to fill in reliably. Unused fields are
  empty and the converter ignores them.
- **The response is streamed, not awaited.** A plan for eight slides takes the
  better part of a minute, and `respond(to:generating:)` shows nothing until it
  is done. Each snapshot becomes a `PlanProgress` and is printed over the
  previous one, so the steps are watched taking shape:

  ```
  Planning...
    3. add slide 3 "Key Features" (5 bullets)
  ```

  `PartiallyGenerated` cannot stand in for the finished plan — every field on it
  is optional — so the plan is rebuilt from the last snapshot's `rawContent`
  rather than from `collect()`, which the loop has already consumed. The bullet
  count is there because it is the only thing that moves while a long body is
  written. Nothing is applied until the whole plan is in hand.
- **Progress is a terminal-only affair.** `Console.progress` rewrites one line
  in place and is silent when stdout is redirected, where carriage returns
  cannot take back what they wrote. Identical snapshots — a dozen in a row
  describe the same step — are not re-printed.
- **The planner cannot emit `createPresentation`.** Documents are `/create`'s
  job, and the omission means every model-driven action is reversible, so
  `/undo` always works on them.
- **Empty means "leave alone" on `updateSlide`**, not "clear". The domain model
  can express clearing; the model cannot reliably signal which it meant, and
  keeping content is the safer reading.
- **The session survives across requests** so follow-ups ("make that shorter")
  have context. On `exceededContextWindowSize` the session is rebuilt and the
  request retried once — the deck outline rides in the prompt, so nothing the
  planner needs is lost.
- **…but not across documents.** The transcript refers to slides by number, and
  after `/close` + `/edit` those numbers describe a deck that is no longer open,
  so attaching or detaching a document resets the conversation — the same reason
  either one clears the undo history. `/save-as` does *not* reset: the file and
  the document id change, but the deck does not. Both call sites go through
  `REPL.attachDocument` / `detachDocument` so a later document command cannot
  pick up the state reset and leave the conversation behind.
- **Slide metadata is re-read between actions.** Each applied action shifts the
  numbers the next one was planned against.
- **A failed step stops the plan.** Later actions assume the slide numbers the
  earlier ones were supposed to produce, so continuing past a failure edits the
  wrong slides. What already applied stays on the undo stack.

---

## AppleScript Renderer Contract

Each `PresentationAction` maps to a fixed AppleScript template. The renderer
substitutes only pre-validated, escaped values. It never interpolates raw model output.

```
AddSlide(index: 3, spec: ...) →
  tell application "Keynote"
    set newSlide to make new slide at after slide 2 of document id "…"
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

### Phase 4 — AI Integration (done)
`FoundationModelClient` · `PresentationPlanner` · `@Generable` action types
· Natural-language input wired to planner in REPL

**Done when:** Typing a NL request creates/edits slides in Keynote end-to-end.

**Theme names turned out not to matter here.** They are localized — on a Korean
system `theme "White"` fails with `-1728` and `theme "흰색"` succeeds — but the
planner never emits `createPresentation`, so no theme name ever reaches the
renderer. Mapping English theme names onto the installed ones becomes real work
only when `/create` grows a theme argument (Phase 6).

### Phase 5 — Polish (done)
Progress display (done) · graceful degradation when Apple Intelligence
unavailable (done) · unsaved-change warning on `/exit` (done) · context window
management (done: proactive round-limit reset + `onConversationReset` callback)

### Phase 6 — Richer Presentations

Phase 6 is split into sequential sub-phases. Each sub-phase has a clear entry
condition; do not begin one before its predecessor is verified.

#### Phase 6a — Keynote Automation Capability Audit (do first, before any code)

Run small AppleScript probes to determine what Keynote actually exposes. Record
every result in `CAPABILITIES.md` in the repo root. That file becomes the
ground truth for all Phase 6b–6f decisions.

| Capability | Probe | Status |
|---|---|---|
| Enumerate master slides | `master slides of document id "…"` | TBD |
| Select master for new slide | `set base slide of newSlide to master slide N` | TBD |
| Read available themes | `themes of application "Keynote"` | TBD |
| Set slide transition | `transition properties of slide N` | TBD |
| Add build animation | `make new build` | TBD |
| Insert and position shape | `make new shape with properties {position: …}` | TBD |
| Insert local image | `make new image with properties {file: …}` | TBD |
| Export to PDF | `export document as PDF to …` | TBD |
| Export to PPTX | `export document as Microsoft PowerPoint to …` | TBD |

**Done when:** every row in `CAPABILITIES.md` has a confirmed Yes/No and a
working or failing probe script.

#### Phase 6b — `/export pdf` and `/export pptx`

Export is independent of the capability audit — Keynote's `export` command is
documented API. New `PresentationAction.exportPresentation(format:path:)`,
renderer template, and `/export pdf [<path>]` / `/export pptx [<path>]` commands.

**Done when:** `/export pdf` produces a readable PDF next to the `.key` file.

#### Phase 6c — Master Slide Selection and `LayoutIntent`

Replace `SlideLayout` (3 cases, controls placeholders only) with `LayoutIntent`
(8 cases, drives both placeholder selection and master slide choice):

```swift
enum LayoutIntent: String, Sendable, CaseIterable, Equatable {
    case titleAndBody   // default
    case blank
    case titleOnly
    case section        // divider slide, large centered text
    case hero           // oversized title, minimal body
    case statement      // single sentence, full-bleed
    case comparison     // two-column body
    case metric         // large number + short label
}
```

Master slide mapping strategy: **index-based, not name-based.** Theme master
names are localized and differ between themes. Instead:

1. After `/create` or `/edit`, `KeynoteController.readMasterSlides()` returns
   `[(index: Int, name: String)]` from the open document.
2. `Session.availableMasters: [MasterInfo]` stores this list.
3. At render time, `AppleScriptRenderer` matches `LayoutIntent` → master index
   by reading the available names (heuristic: "Blank" → `.blank`, first master
   with "Title" and "Content" → `.titleAndBody`, etc.).
4. On no match, fall back to master index 1 silently.

`AppleScriptRenderer.renderAddSlide` gains:
```
set base slide of newSlide to master slide <index> of <document>
```

**Session additions:**
```swift
var availableMasters: [MasterInfo]   // (index: Int, name: String) per theme
```

**Done when:** `addSlide` with `.hero` produces a visually distinct slide from
one with `.titleAndBody` on the same deck.

#### Phase 6d — Theme Awareness

**The localization problem:** Keynote theme names are locale-specific.
`theme "White"` fails with `-1728` on a Korean system; `theme "흰색"` succeeds.
Letting the model emit theme names would make every non-English system unreliable.

**Strategy: user-specified, runtime-matched.** The model never picks a theme.

- `/create <name> --theme <display-name>` takes the name from the user, who
  can read what Keynote shows in their locale.
- At runtime, `KeynoteController.readAvailableThemes()` reads
  `themes of application "Keynote"` and returns `[(index: Int, name: String)]`.
- Keynoter matches the user's string against the live list (case-insensitive
  prefix match; on ambiguity, pick the first). On no match, use the default
  theme and warn.

**Session additions:**
```swift
var availableThemes: [ThemeInfo]     // (index: Int, name: String) from Keynote
```

**Done when:** `/create demo --theme <locale-name>` opens a deck in that theme.

#### Phase 6e — Tool Calling Architecture (experimental)

Current approach: one `streamResponse` call produces a full plan upfront.
Tool calling replaces this: the model calls `addSlide`, `updateSlide`, etc.
one at a time, and Keynoter executes each immediately before the model continues.

Benefits: the model can read slide state between steps; complex plans stay
within context; errors surface one step at a time.
Cost: 8× more model round-trips per request — a full deck takes much longer.

**Do not begin Phase 6e before validating Phase 6c and 6d in production.** The
current structured-generation approach handles the core use case well. Adopt
tool calling only if multi-step plans prove unreliable for complex layouts.

#### Phase 6f — Transitions and Animations

Only if the capability audit (6a) confirms that `transition properties` and
build animations are settable via AppleScript. Otherwise skip.

If feasible:
- New `TransitionSpec` type on `SlideSpec`
- New `AnimationSpec` for build-in / build-out sequences
- Renderer templates for each confirmed scriptable transition type

---

## Safety Checklist (before any execution)

- [ ] Slide index is within current slide count
- [ ] Text fields are free of AppleScript metacharacters (`"`, `\`, `&`)
- [ ] File path is within allowed directories and has `.key` extension
- [ ] The script names its target document by id — no `front document`
- [ ] Action type is in the supported allow-list
- [ ] AppleScript targets Keynote only — no shell or system calls
