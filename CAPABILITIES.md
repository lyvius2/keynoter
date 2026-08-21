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
| Build (entry) animations | ❌ NO | `builds of slide` fails `-1700`; not scriptable |
| Create / insert new shape | ❌ NO | `make new shape at end of shapes of slide` fails `-10000` every time |
| Modify existing shape geometry | ✅ YES | `position`, `width`, `height` are settable on shapes already on a slide |
| Insert a local image | ❌ NO | `make new image with properties {file:…}` fails `-10000` |
| Export to PDF | ✅ YES | `export doc to path as PDF`; document must be saved to disk first; use `front document` reference |
| Export to PPTX | ✅ YES | `export doc to path as Microsoft PowerPoint` |

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

PDF and PPTX export both require the document to be saved to disk.
Use `front document` (not `document id "…"`) for the export call; the id
reference does not survive a save in all cases.

```applescript
tell application "Keynote"
    set exportPath to POSIX file "/path/to/output.pdf"
    export front document to exportPath as PDF
end tell
```

### Build animations

`builds of slide` fails with `-1700`. The Keynote AppleScript dictionary does
not expose build animations. Phase 6f scope is limited to slide transitions.

### Shape and image insertion

`make new shape` and `make new image` both fail with `-10000`
(Apple event processing failed). Keynote's scripting dictionary lists these
as creatable, but creation is not implemented at the Apple Events layer.

**Workaround for future consideration:** pre-populate a master slide with
placeholder shapes in Keynote's GUI; then move/resize them via AppleScript
(which does work). This is out of scope for Phase 6.

---

## Phase 6 Impact

| Phase | Decision |
|---|---|
| 6b `/export pdf` | Proceed — confirmed feasible |
| 6b `/export pptx` | Proceed — confirmed feasible |
| 6c `LayoutIntent` | Proceed — master selection by index is confirmed |
| 6d Theme awareness | Proceed — runtime enumeration confirmed; name matching required |
| 6e Tool calling | Unchanged — API design question, not an AppleScript constraint |
| 6f Transitions | Proceed for **slide transitions only**; build animations are not scriptable |
| 6f Shapes / images | Out of scope — insertion not available via AppleScript |
