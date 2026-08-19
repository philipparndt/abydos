## Why

Stopped at a breakpoint, the values are in the bottom panel and the code is in
the editor, and reading one line of code means moving your eyes between the two
and matching names by hand. Every other debugger worth using puts the value
beside the name it belongs to, because that is where the question is asked:
*what is `count` here?*

**The data is already on this side.** `DebugSession.selectFrame` asks the
adapter for `scopes` and then for each scope's `variables`, keeps them, and
raises `onVariablesChanged`; the pane draws them as a tree. Nothing more has to
be asked of the adapter to put a value at the end of a line — which matters,
because asking is the expensive and the dangerous part: an `evaluate` per line
is a round trip per line, and in some languages it runs code.

**And the editor is already told about the stop.** `EditorViewController`
holds `executionLocation` and pushes per-file debug state into every
`CodeView` — breakpoints, runnable lines, the execution marker — through one
function, `applyDebugState`. The values would ride the same channel, and no new
route between the debugger and the editor is needed.

What is missing is the third piece: nothing in the editor draws anything at the
end of a line. Blame is a *column* to the left of the gutter, so it is not the
mechanism this wants, and there is no inlay-hint machinery in the app at all.

Reported as "during debug it would be nice to see the variables directly in the
source editor". No `.abydos/backlog` item was filed for it.

## What Changes

- **A stopped frame draws its variables at the ends of the lines that name
  them.** `count = 12`, dimmed, after the last character of the line.
- **The matching is textual and costs nothing to ask**: the identifiers on a
  line are matched against the names the adapter already returned for the
  selected frame. **No `evaluate`**, no request per line, and therefore no
  chance of running somebody's code to draw a hint.
- **Only the file and frame that is stopped**, and only up to the stopped line.
  A value that has not been assigned yet is worse than no value: below the
  current line it is either stale from a previous pass or not yet a thing at
  all, and it would be read as fact.
- **The matching is in `AbydosKit`**, over a line of text and a set of
  variables, so the part that decides what is shown is testable without a
  window — the drawing in `CodeView` is then only placement.
- **One line, always.** A struct's value can be a page; a hint that wraps is a
  hint that moves the code. Truncated, with the whole value still in the panel
  where a tree can hold it.
- **Nothing while nothing is stopped.** The map is built when execution stops
  or the frame changes, and thrown away when it resumes — so nothing is
  computed on the typing path, which is where this feature would otherwise be
  paid for.
- **Not proposed: editing a value inline.** Setting a variable is a real
  operation with real consequences and belongs where it can be confirmed.
- **Not proposed: hovering an arbitrary expression to evaluate it.** That is
  `evaluate`, it is a different feature, and it is the one with side effects.
- **Not proposed: a setting to turn this off.** Worth adding when somebody
  wants it off, and not before.

## Capabilities

### New Capabilities
<!-- None. -->

### Modified Capabilities

- `debug-sessions`: what a stopped session shows. The capability covers what is
  on screen while a session is stopped and what is left when it ends; where the
  values are shown is the same subject.

## Impact

- `Sources/AbydosKit/Debug/` — a new type that decides, for one line of text and
  the variables in scope, what should be drawn beside it. No view code.
- `Sources/AbydosApp/Editor/CodeView.swift` — drawing at the end of a row, and a
  setter beside `setExecutionLine` and `setBreakpoints`.
- `Sources/AbydosApp/Editor/EditorViewController.swift` — `applyDebugState`,
  which already pushes the other three pieces of per-file debug state.
- `Sources/AbydosApp/Panel/DebugPane.swift` — where `onVariablesChanged` and
  `observeStopped` are already wired.
- `.abydos/backlog/spec/debugging.md`.
- No new dependency, and no new request to any debug adapter.
