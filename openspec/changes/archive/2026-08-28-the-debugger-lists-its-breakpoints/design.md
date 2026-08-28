# Design

## Context

`DebugPane` is 1,400 lines built around one `DebugSession` handed to its
initialiser, and `makeDebugSession` in `BottomPanel` is the only thing that ever
builds one. A pane therefore exists only for a program, and the window has
nowhere to show anything about debugging while nothing is being debugged.

The set of breakpoints, meanwhile, is one of the few pieces of debugger state
that outlives every session. `DebugCoordinator` holds it in `pendingBreakpoints`,
keeps it in step with a running session's, anchors each one to the code it was
put on when the file is edited, and writes the whole set into
`.abydos/session.json` so it survives the project being closed. Everything about
it is already right except that there is no way to look at it: it is drawn one
file at a time, in the gutter of whichever file is open.

Two constraints come from the repository rather than from the feature. View code
does not go in `AbydosKit`, which is where the tests are — so anything worth a
test has to be a value, not a view. And cost is a design constraint: this list is
rebuilt whenever a breakpoint moves, which is on a debounce after every edit to a
file that has one.

## Goals / Non-Goals

**Goals:**

- Every breakpoint the project has, visible as a list, with the verbs that
  already exist for one reachable from its row.
- The debug pane opens with nothing running, so the list has somewhere to live
  and the rail's button has something to open.
- One place in the window that asks what to debug, and it is not a button whose
  job is to show a pane.

**Non-Goals:**

- Kinds of breakpoint the app does not model. `Breakpoint` is a file and a line;
  exception breakpoints, function breakpoints and watchpoints are not in it and
  are not being added here.
- Grouping, muting or naming groups of breakpoints. `setOtherBreakpoints` is the
  one bulk verb that exists and it gets a home; no new ones.
- Changing what is written to `.abydos/session.json`. The list reads what is
  already kept.
- Anything in the DAP layer.

## Decisions

### The pane's session becomes optional, rather than a stand-in being invented

`DebugPane.session` becomes `DebugSession?`. The stack table, the variables
outline, the watch field and the toolbar's verbs each answer "there is nothing"
when it is nil — which is a state the pane already has to draw correctly, since
`debug-sessions` requires that a session which has ended leaves nothing of the
program on screen. Forty-nine uses of `session.` in the file become guards whose
empty answer is the one already specified.

*Ruled out: an idle `DebugSession` standing in.* It is a smaller diff and it is
the trap this repository has just paid for. `panel.activeDebugSession != nil` is
the window's answer to "is something being debugged": it lights the rail's
ladybird green, enables the stepping verbs in the Debug menu, and decides
`DebugCoordinator.currentDebugSession` — which prefers *a session's* breakpoints
over the pending set. A stand-in with no breakpoints would answer that question
and the project's whole set would be written to its session file as empty on the
next save. Making all eleven callers ask "…but has it launched?" is a rule nobody
can keep, and it is the same shape as the fault fixed this morning: a session
answering for something it does not belong to. With an optional session,
`activeDebugPane?.debugSession` is nil for an empty pane and every one of those
callers is right without being changed.

*Ruled out: a second pane class for the empty case.* Two views drawing one
toolbar, and the moment a session starts the pane somebody is looking at is
replaced by a different class.

### Breakpoints are a tab beside the call stack

The left-hand side of the split gets a segmented control — Stack | Breakpoints —
mirroring the Variables | Console tabs the right-hand side already has, and for
the reason given where those were built: two things that do not fit side by side
at any panel height somebody would choose. The pane opens on Breakpoints when
there is no session and on Stack when there is, which is the same
follow-the-session rule `showVariables` and `showConsole` already keep.

*Ruled out: a third column, always visible.* The pane is already a split of two
at a panel height of a few hundred points; a third column makes each one too
narrow to read a path in, and two thirds of it are empty while nothing is
running.

*Ruled out: a pane of its own beside Debug and Terminal.* The list and the stack
are read together while a program is stopped — "which of these did it hit" — and
the rail is thirty points wide with no button to spare.

### The list reads from `DebugCoordinator`, which learns to say the set changed

The coordinator is already the one place that knows the whole set for the
project, whether or not a program is running, and it already carries every verb a
row needs: `toggleBreakpoint`, `setBreakpoint(file:line:enabled:)`,
`deleteBreakpoint`, `setBreakpointOptions`, `setOtherBreakpoints`. What it lacks
is a way to say the set changed as a whole; the gutter never needed one because
it is told file by file. It gains one hook, fired from the two funnels every
change already passes through — `publishPendingBreakpoints` and
`syncBreakpointsToEditor`.

*Ruled out: the list reading `.abydos/session.json`.* That file is what the set
looks like at the last save; the gutter and the list would disagree for as long
as a write was pending, and a breakpoint deleted from a list that reads a file
would come back.

*Ruled out: the list owning the set itself.* Two owners is the fault this
morning's work was about.

### A row's text is read when the row is asked for, and is never stored

A row shows the file and line, the code on that line, and the condition where
there is one. The code comes from the editor's live document when the file is
open — which is what `anchorBreakpoints` already reads, so an unsaved edit shows
the line as it is now — and from the file otherwise. `NSTableView` asks only for
the rows it draws, and a project has breakpoints in a handful of files, so this
is a handful of reads on opening the list and none on redrawing it.

*Ruled out: persisting `anchor.text` in the session file.* `BreakpointAnchors.Anchor`
already records what was written on the line, but it is not written to disk and
should not be: a file edited by anything while the app was closed would give the
list a line of code that is not on that line any more, and text that is confidently
wrong is worse than a row that shows only its file and line.

*Ruled out: reading every file when the list opens.* Rows nobody scrolls to cost
nothing this way.

### The rows themselves are a value, and live in `AbydosKit`

What the list shows — the set flattened, sorted by path and then line, each named
relative to the project root, with files outside it named in full — is a function
from `[String: [Breakpoint]]` to rows, and it goes in `Sources/AbydosKit/Debug/`
with a test on it. The view draws what it is given. This is the only part of the
feature that can be tested at all: `Tests/` covers `AbydosKit` and nothing in
`AbydosApp`.

### The ways to start a session move into the run control's existing menu

`RunControl` already draws the ladybird and a chevron beside it, and the chevron
already opens a menu of the other ways to start something — Debug, Profile, Run
with Coverage. "Debug Executable…" and "Attach to Process…" join it, with "Debug
Go Package" where the project is a Go one, which is the same question
`ToolWindowBar.isGoProject` asks today. The bodies do not move:
`attachToProcess`, `debugExecutable` and `goDebug` stay on
`MainWindowController` and are wired to the run control instead of to the rail.

`ToolWindowBar.debugButtonPressed` becomes `onToggleDebug?()` and nothing else,
and the strip loses four hooks.

### A session starting replaces the empty pane, as it replaces any other

`makeDebugSession` already closes an existing debug pane before opening its own —
"one debug session at a time; a second would fight over breakpoints" — and an
empty pane is not special. The new pane opens on Stack, because a session
starting is a reason to look at the stack.

*Ruled out: handing the session to the pane that is already open.* It saves a
layout pass nobody sees and buys a second lifecycle to get right, in a class
built around one session for its lifetime.

## Risks / Trade-offs

- **Optional session, forty-nine call sites** → the compiler finds every one of
  them, and each has exactly one right answer: the empty state the pane already
  draws when a session ends. The risk is a `!` written to keep a diff small; the
  reviewer's job is that there are none.
- **A row acts on a breakpoint that has moved** — the file was edited since the
  list was built → every verb is addressed by file and line and goes through
  `DebugCoordinator`, which is the same path the gutter's own context menu takes,
  and anchoring fires on the same debounce for both. The list is rebuilt from the
  coordinator's change hook rather than kept as a snapshot.
- **The list is empty and looks broken** → a project with no breakpoints says so
  in words, with the one sentence that tells somebody how to make one: click a
  gutter.
- **The rail's ladybird is now lit for an empty pane** → allowed by `left-rail`
  as it stands, which already specifies the debug pane in front with no session
  running as a case, and distinguishes it from a running session by colour rather
  than by fill.
- **Losing Attach to Process from the rail** → it stays in the Run menu, where it
  already is, and arrives in the run control's menu, which is where somebody
  looking for "start something" looks. Nothing is only in one place.

## Open Questions

- Whether the Breakpoints tab deserves a menu item and a shortcut of its own —
  IntelliJ's ⌘⇧F8 opens a breakpoints dialogue, and this is a tab rather than a
  dialogue. Left until the tab exists and somebody has tried to reach it twice.
- Whether a breakpoint in a file outside the project — a dependency's source, the
  standard library — should be listed under a heading of its own rather than
  named by its full path. It is one row in a list of a handful today; a project
  where it is not will say so.
