# Keynoter

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

  Command                 Description
  ----------------------- ---------------------------------------------------------
  `/help`                 Show available commands
  `/create {filename}`    Create a new Keynote presentation
  `/edit {path}`          Start editing an existing Keynote presentation
  `/status`               Show the current session and document state
  `/open`                 Open or focus the active document in Keynote
  `/save`                 Save the active presentation
  `/save-as {filename}`   Save the presentation under another name
  `/undo`                 Undo the latest Keynoter operation
  `/redo`                 Reapply the latest undone operation
  `/script`               Show the AppleScript generated for the latest operation
  `/doctor`               Check the local Keynoter environment
  `/close`                Close the active document session
  `/exit`                 Exit Keynoter

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

## Technology

-   **Platform:** macOS
-   **Language:** Swift
-   **Build:** Swift Package Manager
-   **AI:** Apple Foundation Models framework
-   **Presentation:** Apple Keynote
-   **Automation:** AppleScript / Apple Events
-   **Interface:** Interactive CLI / REPL

Xcode is recommended for access to Apple's SDK and Swift toolchain, but
it does not need to be the primary editor.

## Project Status

Keynoter is currently in the **initial design / MVP planning stage**.

The first implementation milestone will focus on:

-   interactive CLI / REPL;
-   Foundation Models integration;
-   structured `PresentationAction` generation;
-   Keynote document creation and editing;
-   deterministic AppleScript rendering;
-   save/open/session management;
-   undo/redo;
-   environment diagnostics;
-   AppleScript inspection.

PDF and PowerPoint export, richer layouts, diagrams, images, themes, and
presentation templates are planned for later phases.

## Development

The current proposed package layout is:

``` text
keynoter/
├── Package.swift
├── CLAUDE.md
├── AGENTS.md
├── README.md
└── Sources/
    └── Keynoter/
        ├── main.swift
        ├── CLI/
        ├── AI/
        ├── Domain/
        ├── Keynote/
        ├── Session/
        └── Diagnostics/
```

For architecture, implementation rules, MVP scope, and current design
decisions, read:

-   [`CLAUDE.md`](./CLAUDE.md)
-   [`AGENTS.md`](./AGENTS.md)

## Planned Next Step

The next design task is to define the `PresentationAction` domain
contract:

-   action types;
-   Foundation Models structured output;
-   validation rules;
-   AppleScript mappings;
-   undo/redo behavior;
-   error/result handling.

------------------------------------------------------------------------

**Keynoter** --- Create and edit Keynote presentations by talking to
your Mac.
