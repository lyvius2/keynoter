# Keynote AppleScript Capability Audit

**Phase 6a** — Probed on macOS 26, Keynote (current App Store version), 2026-08-21.

Each probe was run via `osascript` against a live `.key` document. Results are
ground truth for Phase 6b–6f design decisions.

---

## Results

| Capability | Result | Notes |
|---|---|---|
| Enumerate master slides | ✅ YES | Must iterate index-by-index; `master slides of doc as list` fails `-1700` |
| Set master slide on a slide | ✅ YES | `set base slide of newSlide to master slide N of doc` |
| Read available themes | ✅ YES | `name of theme i of application "Keynote"`; 53 themes on test system |
| Set slide transition | ✅ YES | Property key is `transition effect`, not `transition type`; reading back fails `-1700` — write-only in practice |
| Build (entry) animations | ❌ NO (native builds) | Keynote exposes no build class or creation command; use slide transitions, staged slides, or Magic Move instead |
| Create / insert new shape | ✅ YES | Call `make new shape` inside a `tell slide …` block; `at end of shapes of slide` fails `-10000` |
| Modify existing shape geometry | ✅ YES | `position`, `width`, `height` are settable on shapes already on a slide |
| Insert a local image | ✅ YES | Call `make new image` inside a `tell slide …` block; `at end of images of slide` fails `-10000` |
| Export to PDF | ✅ YES | `export document id "…" to path as PDF`; unsaved edits are included |
| Export to PPTX | ✅ YES | `export document id "…" to path as Microsoft PowerPoint` |

---

## Detail Notes

### Master slide enumeration

```applescript
tell application "Keynote"
    set doc to document id "…"
    set count to count of master slides of doc
    -- iterate 1..count
    set n to name of master slide i of doc
end tell
```

`master slides of doc as list` raises `-1700` (type coercion failure).
Coercing the result element-by-element works.

### Slide transitions

Setting a transition works; reading the value back fails `-1700`. Treat as
write-only. The `dissolve`, `move in`, and `push` constants are accepted.
The correct property record key is `transition effect` (not `transition type`).

```applescript
set transition properties of s to {transition effect:dissolve, transition duration:1.0}
```

### Theme enumeration

Themes live on the `application` object, not the document.

```applescript
tell application "Keynote"
    set n to count of themes
    set themeName to name of theme i
end tell
```

Theme names are **locale-specific** — e.g. "흰색" on a Korean system, "White"
on an English one. Never hard-code them; always match at runtime against the
live list.

### Export

```applescript
tell application "Keynote"
    export document id "…" to POSIX file "/path/to/output.pdf" as PDF
end tell
```

**Corrected 2026-08-21, during Phase 6b.** The first pass recorded that export
needs a `front document` reference and a saved document. Re-probing both claims
found neither holds, and the first one would have made export the only command
in Keynoter aimed at whichever window the user last clicked:

| Re-probe | Result |
|---|---|
| `export document id "…" … as PDF` | ✅ works — no `front document` needed |
| `export document id "…" … as Microsoft PowerPoint` | ✅ works |
| Export with unsaved edits pending | ✅ the edits are in the exported file — no save required |
| Export onto an existing file | ✅ replaced silently, no prompt, no error |
| Export into a folder that doesn't exist | ❌ error **6**, as a localized sentence |

The last row is why `/export` checks the destination folder in Swift: Keynote's
own answer is locale-dependent prose, and Keynoter can say "No such folder:
<path>" instead.

### Build animations

Re-probed on 2026-08-22 with Keynote 14.2 (7041.0.109). The supported Keynote
AppleScript dictionary exposes no build class, element, creation command, or
object-animation property. Resolving `builds of slide` as an object fails with
`-1700`, while `make new build` treats `build` as an undefined variable and
fails with `-2753`.

This means Keynoter cannot add Keynote's native **Build In**, **Build Out**, or
**Action** effects through the supported Apple Events interface. It does *not*
mean that every animation-like presentation is impossible. The supported,
deterministic alternatives are:

- Apply ordinary slide transitions such as dissolve, push, wipe, or move in.
- Reveal content in stages across consecutive slides.
- Duplicate a slide, change an item's position, size, or opacity on the copy,
  and apply **Magic Move** to the source slide.

The last pattern was live-probed: Keynote duplicated the slide, accepted the
shape geometry and opacity changes, and accepted `magic move` as the source
slide's transition effect.

These are confirmed AppleScript capabilities, not features already implemented
in Keynoter. Native builds remain out of scope, and GUI scripting through
`System Events` is intentionally excluded because it is permission-heavy,
locale-dependent, and incompatible with the deterministic renderer boundary.

### Shape and image insertion

Both shapes and local images can be created when the `make` command runs inside
the target slide's `tell` block:

```applescript
tell application "Keynote"
    tell slide 1 of document id "…"
        set newShape to make new shape with properties ¬
            {position:{160, 180}, width:360, height:180, object text:"Shape probe"}
        set newImage to make new image with properties ¬
            {file:POSIX file "/path/to/image.png", position:{120, 140}, width:320}
    end tell
end tell
```

Re-probed 2026-08-22. The shape count increased from 1 to 2, and its position,
width, height, and text all read back correctly. The image count increased from
0 to 1, and its file name, position, and width read back correctly.

The original probes used `make new shape at end of shapes of slide` and the
equivalent `image` form. Those forms still fail with `-10000`; the error means
the insertion location is invalid here, not that creation is unsupported.

## Phase 6 Impact

| Phase | Decision |
|---|---|
| 6b `/export pdf` | **Done** — targets the document by id, like everything else |
| 6b `/export pptx` | **Done** |
| 6c `LayoutIntent` | Proceed — master selection by index is confirmed |
| 6d Theme awareness | Proceed — runtime enumeration confirmed; name matching required |
| 6e Tool calling | Unchanged — API design question, not an AppleScript constraint |
| 6f Animation | Proceed with transitions, staged slides, and Magic Move; native object builds are not scriptable |
| Shapes / images | Feasible — creation is confirmed inside a `tell slide …` block; phase scope remains undecided |
