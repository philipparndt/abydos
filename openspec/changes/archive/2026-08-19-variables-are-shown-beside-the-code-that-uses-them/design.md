## Context

Three things exist already and this change is mostly the wiring between them.

**The values.** `DebugSession.selectFrame(id:)` asks for `scopes`, drops any
whose name contains "registers", and fills each with `variables(reference:)` —
name, value, type, and a reference for children. It runs on a stop and again
whenever the frame changes, and raises `onVariablesChanged` on the main thread.
`DebugPane` builds its tree from exactly this.

**The route to the editor.** `EditorViewController` keeps
`executionLocation: (file, line)?` and `applyDebugState(to:)` pushes per-file
state into each tab's `CodeView`: `setBreakpoints`, `setRunnableLines`,
`setExecutionLine`. Paths are canonicalised — `/tmp` is a symlink to
`/private/tmp`, and a file reached through a symlinked directory used to match
nothing.

**The drawing.** `CodeView` is a monospaced grid: `charWidth` is one advance,
and the blame column is `ceil(18 * charWidth)`. So the x of the end of a line is
arithmetic, not layout — which is what makes an end-of-line annotation cheap.
Blame is drawn as a column *left* of the gutter and is not the mechanism here.

**And there is already an annotation at the end of a line**, which this design
originally said there was not: `drawInlineDiagnostic` draws a language server's
message past the glyphs, dimmed, truncating rather than wrapping, and gives up
when fewer than eight characters of room are left. Everything below follows it.

The cost rule this sits under is the house one: anything on a drawing path is
written knowing it, and there is a timed test asserting the editor draws fast
enough to do while somebody types.

## Goals / Non-Goals

**Goals:**

- The value of a variable is readable beside the code that names it, while
  stopped.
- Nothing is asked of the debug adapter that is not asked already.
- What is shown is decided by testable code, not by a view.
- Nothing is computed while nothing is stopped.

**Non-Goals:**

- Evaluating expressions, or anything that can run the debuggee's code.
- Setting a variable from the editor.
- Values for frames other than the selected one, or files other than its own.
- A hint that changes where the code is drawn: this is drawn after the line, and
  the line does not move.

## Decisions

**Textual matching against the variables already fetched — not `evaluate`.**
This is how it can be free. The adapter has already answered `scopes` and
`variables` for the selected frame, so a name on a line either is one of those
names or it is not. `evaluate` per line is a round trip per line, on the
adapter's queue, while somebody scrolls — and in several languages it *runs
code*: a Java getter, a Python `__repr__`, a Go method. Drawing a hint must not
be able to change the program being debugged. Ruled out for that reason first
and cost second.

**Only up to the stopped line.** The value of a variable on a line below the
current one is either left over from a previous pass or has not been assigned at
all, and it is drawn in the same grey as the one above it, which reads as fact.
IDEs differ here; the honest answer is the one that cannot mislead. Above the
stopped line the values are what they are now, which is the question being
asked.

**Only the frame's own file.** A variable is in scope in the frame it belongs
to. The file of the selected frame gets values; every other tab gets none, the
same way the execution marker belongs only to the file execution stopped in.
Following the *selected* frame rather than the top one is deliberate: clicking a
frame in the stack is asking "what did it look like there".

**The decision lives in `AbydosKit`, the placement in `CodeView`.** A function
over a line of text and the variables in scope, answering what to draw and where
— that is the part with edge cases (a name inside a string, a name that is a
substring of a longer identifier, a name appearing twice) and the part a suite
can hold. The view then draws the strings it is handed. Putting the matching in
the view would make every one of those cases a screenshot.

**And not after a dot** — decided while implementing, and stricter than the
spec's word-boundary rule rather than in tension with it. `self.count` and
`shape.width` are members of something else, and drawing the local `count`'s
value beside an expression about a field that happens to share its name is
exactly the failure this feature must not have. The receiver is still matched:
`count.description` is a hint about `count`.

**`onVariablesChanged` had to become a list.** It is a single closure and
`DebugPane` sets it to rebuild its tree; the editor wants the same moment. A
second `=` would have left whichever ran last as the only one told — silently,
and looking exactly like a feature that does not work. `observeVariables`
follows `observeState` and `observeStopped`, which are lists for the same
reason.

**Word boundaries, not `contains`.** `count` must not match `counter`,
`account`, or `count` inside `"count"` in a string literal. The tokens on a line
are identifier-shaped runs, and a match is a whole token. This is what the tests
in the kit are for.

**A map built on stop, not a search per row.** The variables of a frame are a
dictionary by name, built once when `onVariablesChanged` fires. A row's draw is
then a scan of that row's tokens against a dictionary, which is what the
existing per-row work already costs. Nothing at all is done while no session is
stopped: the map is nil and the drawing is one `guard`.

**One line, truncated, dimmed, after the last character.** Never wrapped, never
between the code and the right edge of the window: a hint that pushes text
around is a hint that makes the file look edited. Where several variables are
named on a line, they are joined in the order they appear on it — reading order
is the only order that means anything here.

**Nothing for a variable whose value is enormous or multi-line.** A `[]byte` of
four kilobytes is not a hint. Truncated with an ellipsis at a fixed budget, with
the tree in the panel as the place that holds the whole thing.

## Risks / Trade-offs

- **A name on a line that is not the variable in scope** — a field of another
  object, a shadowed name in a nested closure, a name in a comment. → Word
  boundaries and the frame's own scope cut most of it; a comment is not
  distinguished, and that is a known limitation rather than a hidden one. The
  syntax highlighter already knows which spans are comments and strings, so a
  later refinement has somewhere to come from.
- **Drawing cost per row.** → The map is a dictionary, the work is per visible
  row and only while stopped, and the timed drawing test stands over it. If it
  does not hold, the fallback is to draw only the stopped line, which is the
  line somebody is looking at anyway.
- **A long line with a long value** pushes the hint off the right edge. → It is
  clipped, like anything else drawn past the edge; the value is in the panel.
- **Adapters that return values in odd shapes** — Delve's struct summaries, JDI's
  `Object@1234`. → Whatever the adapter said is what is shown, unchanged: this
  displays the same string the tree does, and inventing a prettier one is a
  second formatter to keep true.

## Open Questions

- **Should a hint be clickable — to expand into the tree, or to add a watch?**
  Plausible and not asked for. It would want a hit-test region per hint, which
  is a different piece of machinery from drawing one.
- **Should comments and string literals be excluded using the highlighter's
  spans?** They can be, and it is a strictly better answer than word boundaries
  alone. Left out of the first pass because it couples the matching to the
  highlighter and the matching is meant to be testable without one.
- **What about the line the frame *returned* to** — the call site in a parent
  frame, where the interesting value is the one being returned? Nothing is drawn
  there today under this design, and it may be the most useful hint of all.
