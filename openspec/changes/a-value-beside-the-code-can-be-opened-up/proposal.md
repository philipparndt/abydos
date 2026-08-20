## Why

The values beside the code answer the question for an `Int` and give up on
everything else. Photographed in `go-service`, stopped in `main`:

    mux := http.NewServeMux()    mux = *net/http.ServeMux {mu: sync.RWMutex {w:…
    started := time.Now()        started = time.Time(2026-08-20T05:19:47Z, +1213631…

`stage = "local"` is the whole answer. The other two are a type name and the
first forty characters of a struct, cut mid-word — enough to say *there is
something here* and nothing else. A truncated value is not a small answer, it is
a pointer to the panel: the tree at the bottom of the window has the same
variable with its fields under it, so the reading somebody actually does is to
go down there and find it again by name.

Recorded as an open question when the values were added — *"should a hint be
clickable, to expand into the tree?"* — and left out then because nothing had
asked for it. Now it has.

## What Changes

- **A value beside the code can be opened.** Clicking one whose variable has
  children opens a small window on that variable, with its fields under it,
  expandable — the same tree the panel draws, over the same frame.
- **Only where there is something to open.** The adapter says so:
  `variablesReference > 0` is a container and everything else is a leaf.
  `stage = "local"` stays a piece of text; `mux` becomes something to press.
- **It says so before it is pressed**, by the pointer over it and by the hint's
  own weight, so the difference between a value and a door is visible without
  clicking everything on the line.
- **Children are fetched when it opens, not when the line is drawn.** A
  `variables` request per hint per repaint is what makes an editor unusable
  while stopped; on a click it is one request, made because somebody asked.
- **Nothing about the line changes.** Same text, same place, same truncation —
  what is added is a way in, not a longer sentence.
- **Not proposed: making the hints wider or the truncation cleverer.** A struct
  does not fit at the end of a line at any budget, and the fix for "there is
  more than fits" is a place with room in it.
- **Not proposed: editing a value from the popup.** Setting a variable is a real
  operation with consequences and belongs where it can be confirmed. This is a
  reader.
- **Not proposed: replacing the panel's tree.** It stays, it is the place for
  reading a whole frame, and this is the place for reading one variable without
  leaving the line it is on.

## Capabilities

### New Capabilities

<!-- None. -->

### Modified Capabilities

- `debug-sessions`: the requirement that a stopped frame shows its variables
  beside the code says what is drawn and how loudly. What can be done with what
  is drawn is the same subject, one step on.

## Impact

- `Sources/AbydosApp/Editor/CodeView.swift` — the hints are drawn as one
  joined string today and nothing knows where each one is; opening one needs a
  rect per hint, a click, and a cursor.
- `Sources/AbydosKit/Debug/InlineValues.swift` — a hint carries a name and a
  string; to open one it has to carry the variable's reference too, which means
  `InlineValueSet` holding `Variable`s rather than a `[String: String]`.
- `Sources/AbydosApp/Panel/DebugPane.swift` — the tree, its lazy expansion and
  its row drawing are here, and the popup wants the same behaviour rather than a
  second one.
- `Sources/AbydosKit/Debug/DebugSession.swift` — `variables(reference:)` and
  `toggleExpansion` already fetch children; a popup over a variable outside the
  panel's tree needs the same fetching without the panel's indices.
- `.abydos/backlog/spec/debugging.md`.
- No new dependency, and no new kind of request to any adapter.
