# Keynoter --- Development Guide

## 1. Project Overview

**Keynoter** is a macOS-native conversational CLI for creating and
editing Apple Keynote presentations with Apple's on-device Foundation
Models.

The primary execution flow is:

``` text
User Prompt
    ↓
Keynoter CLI
    ↓
Apple Foundation Models
    ↓
Structured Presentation Actions
    ↓
Swift Action Engine
    ↓
AppleScript Renderer
    ↓
AppleScript / Apple Events
    ↓
Keynote
    ↓
.key File
```

Keynoter should feel like an agentic developer CLI such as Claude Code,
but its working artifact is a Keynote presentation.

## 2. Core Principles

-   Target macOS first.
-   Implement the application in Swift.
-   Use Apple Foundation Models / Apple Intelligence as the primary AI
    path.
-   Keep inference on-device whenever supported.
-   Do not require Ollama or an external inference server for the
    primary workflow.
-   Use natural language for presentation content, structure, and design
    changes.
-   Use slash commands for application, session, file, and diagnostic
    operations.
-   Do not execute arbitrary AppleScript generated directly by the model
    in the normal workflow.
-   Prefer structured model output followed by deterministic validation
    and rendering.
-   Make automation transparent: users must be able to inspect the
    generated AppleScript.
-   Treat the currently active Keynote document as explicit session
    state.

## 3. Architecture

``` mermaid
flowchart TD
    U[User] --> CLI[Keynoter CLI / REPL]
    CLI --> FM[Apple Foundation Models]
    FM --> PA[PresentationAction / PresentationSpec]
    PA --> VE[Validation Engine]
    VE --> AE[Swift Action Engine]
    AE --> AR[AppleScript Renderer]
    AR --> EX[AppleScript Executor]
    EX --> KN[Apple Keynote]
    KN --> KF[".key File"]

    CLI --> SM[Session Manager]
    SM --> KF
    AR --> SC["/script"]
```

### Foundation Models

The model is responsible for understanding **what the user wants**.

Examples:

-   Create an eight-slide architecture presentation.
-   Add a TO-BE Architecture slide after slide 3.
-   Shorten slide 4 to three key points.
-   Rewrite the entire deck for an executive audience.
-   Reorganize the story into Problem → Architecture → Migration
    Strategy.

Prefer structured generation over free-form executable code.

### Swift Action Engine

The Action Engine validates and performs supported presentation
operations.

Conceptual actions include:

``` text
CreatePresentation
AddSlide
UpdateSlide
DeleteSlide
MoveSlide
ChangeLayout
ChangeTheme
UpdateSpeakerNotes
ExportPresentation
```

### AppleScript Renderer

The renderer converts validated domain actions into deterministic
AppleScript.

The model decides **intent and content**.

Keynoter decides **how Keynote is controlled**.

## 4. AI Execution Model

### Do not use this as the normal path

``` text
Prompt
  ↓
Foundation Models
  ↓
Arbitrary AppleScript
  ↓
osascript
  ↓
Keynote
```

### Preferred path

``` text
Prompt
  ↓
Foundation Models
  ↓
PresentationAction / PresentationSpec
  ↓
Schema Validation
  ↓
Semantic Validation
  ↓
Swift Action Engine
  ↓
AppleScript Renderer
  ↓
AppleScript
  ↓
Keynote
```

This boundary is a core architectural rule.

## 5. Technology Stack

  -----------------------------------------------------------------------
  Area                                Technology
  ----------------------------------- -----------------------------------
  Language                            Swift

  Build / Package                     Swift Package Manager

  AI                                  Apple Foundation Models framework

  Model                               Apple on-device system language
                                      model

  Presentation App                    Apple Keynote

  Automation                          AppleScript / Apple Events

  Script Execution                    `osascript` or appropriate native
                                      macOS scripting APIs

  Interface                           Interactive CLI / REPL

  Platform                            macOS

  IDE                                 Optional; Xcode installation is
                                      recommended for Apple SDK/toolchain
                                      access
  -----------------------------------------------------------------------

Xcode does not have to be the primary editor. Development may be
performed from another editor or coding agent while using the Apple SDK
and Swift toolchain installed with Xcode.

## 6. CLI Interaction Model

Launch:

``` text
$ keynoter

Keynoter
On-device AI presentation assistant for Apple Keynote

> _
```

Natural-language input changes the presentation.

Slash commands control Keynoter itself.

Example:

``` text
> /create msk-migration

Created: ./msk-migration.key

> Create an 8-slide presentation about AWS MSK Migration Architecture.
  The audience is software engineers.
  Include AS-IS, TO-BE, and Migration Strategy.

Planning presentation...
Generating 8 slides...
Applying changes to Keynote...

✓ Presentation updated.
```

## 7. MVP Slash Commands

### `/help`

Display commands and usage.

### `/create {filename}`

Create a new Keynote presentation and make it the active document.

``` text
> /create msk-migration
```

Subsequent natural-language prompts operate on this document.

### `/edit {path}`

Open an existing `.key` presentation and make it the active document.

``` text
> /edit ~/Documents/msk-migration.key
```

Keynoter should inspect enough document metadata to understand the
existing slide structure before applying modifications.

### `/status`

Display the active session state.

``` text
> /status

Document : ./msk-migration.key
Mode     : EDIT
Slides   : 8
Modified : Yes
Model    : Apple On-Device Foundation Model
Undo     : 3 operations available
```

### `/open`

Open or bring the active presentation to the foreground in Keynote.

The intended workflow is to keep Terminal and Keynote visible together
while iterating conversationally.

### `/save`

Save the active presentation.

``` text
> /save
✓ Saved ./msk-migration.key
```

### `/save-as {filename}`

Save the active presentation under another name.

``` text
> /save-as msk-migration-final.key
```

### `/undo`

Undo the most recent Keynoter-driven presentation operation.

Prefer application-level action history rather than relying exclusively
on Keynote's UI undo stack.

### `/redo`

Reapply the most recently undone Keynoter operation.

### `/script`

Display the AppleScript generated for the most recent operation.

``` text
> Change the title of slide 3 to "Migration Strategy".

✓ Updated slide 3

> /script

tell application "Keynote"
    tell slide 3 of document 1
        set object text of default title item to "Migration Strategy"
    end tell
end tell
```

`/script` should show AppleScript produced by the deterministic
renderer, not arbitrary model-generated code.

### `/doctor`

Validate the runtime environment.

Example checks:

``` text
macOS                  supported
Apple Silicon          available
Apple Intelligence     available
Foundation Models      available
Keynote                installed
Automation Permission  granted
Swift Toolchain        available
```

### `/close`

Close the current document session while keeping Keynoter running.

### `/exit`

Exit Keynoter.

If unsaved changes exist, warn the user before termination.

## 8. Post-MVP Commands

### `/export pdf`

Export the active presentation as PDF.

### `/export pptx`

Export the active presentation as PowerPoint.

Potential syntax:

``` text
/export pdf
/export pptx
/export pdf ./output/demo.pdf
/export pptx ./output/demo.pptx
```

## 9. Natural-Language Operations

Do not create slash commands for routine slide editing.

Avoid:

``` text
/add-slide
/delete-slide
/change-title
/update-body
/move-slide
```

Prefer:

``` text
> Add a TO-BE Architecture slide after slide 3.

> Delete slide 5.

> Change the title of slide 2 to "Background".

> Slide 4 has too much text. Keep only the three most important points.

> Rewrite the whole presentation to be more concise for an executive audience.
```

Interaction domains:

``` text
Slash Commands
    └── Application / File / Session Control

Natural Language
    └── Presentation Content / Structure / Design
```

## 10. Initial Domain Model

Conceptual presentation model:

``` swift
struct PresentationSpec: Codable {
    let title: String
    let subtitle: String?
    let slides: [SlideSpec]
}

struct SlideSpec: Codable {
    let title: String
    let body: [String]
    let layout: SlideLayout
    let speakerNotes: String?
}

enum SlideLayout: String, Codable {
    case title
    case bullets
    case section
    case comparison
    case diagram
}
```

When implementing Foundation Models integration, prefer structured
generation using Swift-native schema/guided-generation capabilities
where practical instead of depending on fragile free-form JSON parsing.

## 11. Presentation Actions

Editing should use an action-oriented domain model rather than
regenerating the complete presentation state for every change.

Conceptual hierarchy:

``` text
PresentationAction
├── CreatePresentation
├── AddSlide
├── UpdateSlide
├── DeleteSlide
├── MoveSlide
├── ChangeLayout
├── ChangeTheme
├── UpdateSpeakerNotes
└── ExportPresentation
```

Conceptual structured result:

``` json
{
  "action": "UpdateSlide",
  "slide": 3,
  "changes": {
    "title": "Migration Strategy"
  }
}
```

The Action Engine must validate the result before rendering AppleScript.

## 12. Safety Rules

Never execute unrestricted model-generated AppleScript in the standard
execution path.

Required pipeline:

``` text
Foundation Models
      ↓
Structured Action
      ↓
Schema Validation
      ↓
Semantic Validation
      ↓
Allowed Action Check
      ↓
AppleScript Renderer
      ↓
Execution
```

Validation should include, as applicable:

-   referenced slide exists;
-   requested action is supported;
-   target path is valid;
-   overwrite behavior is intentional;
-   generated text has reasonable bounds;
-   automation targets Keynote only;
-   presentation text cannot inject shell commands or AppleScript;
-   path and text values are escaped correctly.

A future developer/debug mode may permit raw AppleScript experiments,
but it must be explicit and isolated from the normal workflow.

## 13. Session State

Keynoter maintains an in-memory session.

Conceptual structure:

``` text
Session
├── activeDocument
├── mode
│   ├── CREATE
│   └── EDIT
├── modified
├── slideMetadata
├── lastPrompt
├── lastActions
├── lastAppleScript
├── undoStack
└── redoStack
```

This state supports `/status`, `/script`, `/undo`, and `/redo`.

## 14. Suggested Swift Package Structure

``` text
keynoter/
├── Package.swift
├── CLAUDE.md
├── AGENTS.md
├── README.md
└── Sources/
    └── Keynoter/
        ├── main.swift
        │
        ├── CLI/
        │   ├── REPL.swift
        │   ├── Command.swift
        │   └── CommandParser.swift
        │
        ├── AI/
        │   ├── FoundationModelClient.swift
        │   ├── PresentationPlanner.swift
        │   └── PromptBuilder.swift
        │
        ├── Domain/
        │   ├── PresentationSpec.swift
        │   ├── SlideSpec.swift
        │   └── PresentationAction.swift
        │
        ├── Keynote/
        │   ├── KeynoteController.swift
        │   ├── AppleScriptRenderer.swift
        │   └── AppleScriptExecutor.swift
        │
        ├── Session/
        │   ├── Session.swift
        │   └── History.swift
        │
        └── Diagnostics/
            └── Doctor.swift
```

This structure is an initial proposal and may evolve as implementation
boundaries become clearer.

## 15. MVP Scope

### Phase 1

Implement commands:

``` text
/help
/create
/edit
/status
/open
/save
/save-as
/undo
/redo
/script
/doctor
/close
/exit
```

Implement natural-language capabilities:

-   generate a complete presentation;
-   add a slide;
-   edit a slide;
-   delete a slide;
-   rewrite slide content;
-   modify presentation-wide tone/content.

### Phase 2

Add:

``` text
/export pdf
/export pptx
```

Improve:

-   layout selection;
-   theme handling;
-   speaker notes;
-   diagrams;
-   image generation/insertion;
-   richer presentation inspection.

### Phase 3

Potential capabilities:

-   presentation templates;
-   reusable organization styles;
-   slide-level context awareness;
-   document-wide visual consistency checks;
-   automatic presentation review;
-   presentation summarization;
-   reference-document ingestion;
-   richer agent/tool calling.

## 16. Example User Journey

``` text
$ keynoter

> /doctor
✓ Ready.

> /create aws-msk-migration
✓ Created aws-msk-migration.key

> Create an 8-slide presentation about AWS MSK Migration Architecture
  for software engineers. Include AS-IS, problems, TO-BE Architecture,
  and Migration Strategy.

Planning...
Generating presentation...
Applying 8 slides...

✓ Done.

> /open
✓ Opened in Keynote.

> Slide 4 has too much content.
  Keep the three most important points and make it architecture-focused.

✓ Slide 4 updated.

> /script
[Generated AppleScript]

> /undo
✓ Reverted slide 4.

> /redo
✓ Reapplied slide 4.

> /save
✓ Saved aws-msk-migration.key

> /exit
```

## 17. Current Architectural Decisions

These decisions are the baseline unless explicitly changed:

1.  The product name is **Keynoter**.
2.  The executable command is `keynoter`.
3.  Keynoter is a macOS CLI.
4.  Swift is the primary implementation language.
5.  Apple Foundation Models / Apple Intelligence is the primary AI path.
6.  Keynote manipulation uses AppleScript / Apple Events.
7.  The UX is a conversational REPL inspired by agentic coding CLIs.
8.  Slash commands are reserved for application/session/file operations.
9.  Presentation changes are primarily expressed in natural language.
10. The model produces structured presentation intent/actions rather
    than unrestricted AppleScript.
11. AppleScript is generated by a deterministic Swift renderer.
12. `/script` exposes the actual rendered AppleScript for transparency
    and debugging.
13. The MVP prioritizes creation, editing, persistence, history, and
    diagnostics.
14. Export and advanced visual capabilities are post-MVP.
15. The primary workflow must not require Ollama or an external
    inference server.

## 18. Open Design Questions

Do not silently invent permanent answers to these questions. Resolve
them deliberately during detailed design:

-   How should existing `.key` files be inspected and converted into
    model context?
-   Should AppleScript execute once per action or in batches?
-   How should undo/redo state be represented and persisted?
-   How much presentation context should be sent to the on-device model?
-   How should slide identifiers remain stable after moves and
    deletions?
-   How should Keynote themes and layouts map to domain types?
-   Should `/create` immediately persist an empty `.key`, or wait for
    the first successful generation?
-   What happens when the user manually edits Keynote while a CLI
    session is active?
-   How should CLI/Keynote state conflicts be detected?
-   Should auto-save be supported?
-   How should progress be displayed for longer generation operations?
-   How should model-unavailable and Apple-Intelligence-disabled states
    degrade gracefully?

## 19. Next Design Priority

Before broad implementation, define the `PresentationAction` contract in
detail:

1.  supported action types;
2.  structured input/output schemas;
3.  validation rules;
4.  Foundation Models structured-generation contract;
5.  action-to-AppleScript mappings;
6.  undo/redo semantics;
7.  error and result model.

The architectural core is:

``` text
Apple Foundation Models
        ↕
PresentationAction
        ↕
Swift Action Engine
        ↕
AppleScript Renderer
        ↕
Apple Keynote
```

When implementing new features, preserve these boundaries unless there
is a documented reason to change them.
