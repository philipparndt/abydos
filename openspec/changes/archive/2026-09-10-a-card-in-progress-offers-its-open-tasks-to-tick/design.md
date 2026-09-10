## Context

What is on disk already, and what each is for:

    BacklogItem.progress(in:)     counts `- [ ]` against `- [x]` over any markdown; the
                                  one function both records' fractions come from
    BacklogItem.remainingSteps    the unticked steps as text, printed by `done`
    BacklogCard, OpenSpecCard     everything a card says, read on the walk and never
                                  while drawing; `BacklogCard.source` says whether the
                                  checklist came from the project or the worktree
    BacklogColumnView             one NSTableView per column, a BacklogCardView per row;
                                  double-click opens, right-click menus, drag moves
    FileSystemWatcher             both records' directories are watched, and a tick made
                                  in a terminal already moves a card
    StyledTip / TipHost           the app's drawn tooltip: a child NSPanel at
                                  .popUpMenu level that ignores the mouse, shown after
                                  half a second from a TipHost's hit test
    CompletionPopup               the one child panel here that takes the mouse without
                                  taking focus: .nonactivatingPanel, ignoresMouseEvents
                                  false, and a writeImageForTesting because a child
                                  window is invisible to a capture of the main one
    OpenSpec.inProgressCommands   the three sentences a part-way change offers, of which
                                  "complete <name>, I have verified it" is the
                                  all-at-once version of this

Two constraints shape the rest. **No view code in AbydosKit**, so which line is
ticked and what the file becomes is a value the tests hold without a window.
**Cost is a design constraint**: a board redraws on every scroll, and the walk
that reads every card's fraction runs on every write under either directory —
so nothing here reads a file while drawing, and the tip reads its list once,
when it opens.

## Goals / Non-Goals

**Goals:**

- A card in progress, hovered, lists its open tasks and lets each be ticked.
- A tick writes one line of the right file and nothing else, and the board
  follows as it would any other write.
- The tip is in the app's own type and ground, appears on the app's own delay,
  and can be read and driven without a screenshot.

**Non-Goals:**

- Unticking, reordering, or editing a task's words. The file is the editor.
- The tip on Ready, Complete, Writing, Waiting or Archived cards.
- Changing `StyledTip`. It ignores the mouse on purpose and keeps doing so.
- Ticking on the list view's rows. The list is for reading; the board is where
  a card is looked at, and one place to tick is one behaviour to keep.

## Decisions

### 1. A tick is a line number, not a match on the words

`remainingSteps` returns the steps' text, which is what `done` prints. Ticking
by text was the first idea and it fails on the second duplicate: a change whose
tasks say `- [ ] Tests` under three headings has three lines that match, and
the wrong one ticked is worse than none. So the open steps gain their line
index — `BacklogItem.OpenStep(line: Int, text: String)` — and the tick is
`BacklogItem.ticking(line:in:) -> String?`, a pure function over the markdown
that returns the new text, or `nil` when that line no longer reads as an
unticked step.

The `nil` is the guard against a stale tip. The list was read when the tip
opened; an agent in a worktree may have rewritten the file since, and the line
the box stood for may now be a different task or ticked already. When the
guard refuses, nothing is written, the tip reloads its list from the file, and
the person sees what is there now. Writing the matched text as a second check
was considered and dropped: the line either still reads `- [ ]` with those
words or it does not, and the function sees both.

The rewrite keeps everything else byte for byte — the bullet character, the
indentation, the continuation lines, the trailing newline or its absence —
because the file is committed and a diff that shows one character is the diff
somebody expects to see. `[ ]` becomes `[x]`, lower case, which is what
`openspec` and every hand here writes.

### 2. The file written is the one the card's fraction came from

`backlog` says a card's progress is the worktree's, and says so on the card.
A tick from that card that went to the project's copy would tick a step the
card was not showing, on a copy whose fraction the card was not drawing, and
the fraction on the card would not move. So each card carries the URL its
checklist was read from — `BacklogCard` from `run?.itemInWorktree ?? item`,
which it already chooses between, and `OpenSpecCard` from
`change.tasksFile` — and the tip writes there.

A worktree copy that is gone by the time the box is clicked is the stale case
above: the write fails, the tip says the file could not be written and names
it, and the next walk draws the card from the project's copy, `in the project`,
as the spec already says it must.

### 3. The tip is its own panel, not `StyledTip`, and it takes the mouse

`StyledTip` is a `Tip` of three strings drawn into a panel that ignores the
mouse, and the comment on that line says why: a tip that answered the pointer
would keep itself alive after the pointer left the control it is about. A list
of boxes has to answer the pointer, so this is a second panel, `TaskTip`, in
the same shape — borderless, non-activating, `.popUpMenu`, a child of the
window, the sidebar's ground and edge, the same delay and the same placement
under the card's leading edge, above it where there is no room below — with
`ignoresMouseEvents = false`, the way `CompletionPopup` is.

Extending `StyledTip` with an optional list was considered. It would put a
mouse-taking mode into a type whose one guarantee is that it never takes the
mouse, and every caller of `TipHost` would inherit a code path it does not
want. Two panels that share a look through `Theme` cost one more file; one
panel with two natures costs a rule.

**What keeps it open and what closes it.** The tip stays while the pointer is
on the card that opened it or inside the tip, and the two are bridged by a
grace of a quarter second so that crossing the gap between them does not close
it — measured, the gap is six points and a pointer crosses it in well under
that. It closes when the pointer has been on neither for that long, on a click
anywhere that is not the tip, when the column scrolls, when a drag begins, when
a menu opens, when the board reloads with the card no longer in progress, and
when the window resigns key. `NSEvent` local monitors for `leftMouseDown` and
`scrollWheel`, as the completion popup uses, are how the clicks and scrolls
outside a non-activating panel are seen.

**A driven run must not have to hover.** The tip's list and its tick are
methods on the pane — `taskTipReportForTesting(card:)` and
`tickOpenTaskForTesting(card:index:)` — that go through the tip's own open
and its own click handler, so what is driven is what the pointer does, as
`TipHost.hoverForTesting` insists. The verbs are declared on the pane, whose
state they read, and `MainWindowController` only forwards, per `screenshots`.

### 4. Hover tracking lives on the column, and asks the row

`BacklogCardView` is a cell view the table recycles, so a tracking area per
card would be a tracking area per recycled view with the wrong entry in it.
The column already owns the table and its entries, so the column gets one
`NSTrackingArea` with `mouseMoved` and `mouseExited`, hit-tests the row under
the pointer, and hands the tip the entry — or nothing. The tip keys on the
entry's identity (a number, or a name) rather than the view, so a reload that
rebuilds the rows under a still pointer does not restart the delay, exactly as
`StyledTip.show` refuses to for the same tip.

Only rows whose entry is in progress are handed over. That is one `switch` on
`BoardEntry.column` and costs nothing per move; the file is not read until the
delay has elapsed and the tip is about to open.

### 5. The list is read when the tip opens, and re-read on every reload

Reading `tasks.md` on every pointer move was never on the table. The tip reads
the file once, on opening, on the main thread — a `tasks.md` is a few
kilobytes and one read per hover is the cost of the feature — and holds the
`[OpenStep]` it drew. When the board reloads while the tip is open (which a
tick causes, through the watcher), the tip re-reads and redraws, so a row
ticked by an agent in a terminal disappears from an open tip as it would from
the card. If the entry is no longer in progress after the reload, the tip
closes.

The tip lists at most what fits a third of the screen's height and scrolls
past that. A change here has had thirty open tasks; a thirty-row panel over a
five-column board hides the board, and a panel capped at twelve rows with
"and eighteen more" hides the tasks somebody most wants to reach, since the
last are the manual ones. A scrolling `NSTableView` in a panel is what the
completion popup is, and the same construction is used.

### 6. Each row is a drawn box and the step's first line

Rows are drawn, not `NSButton` checkboxes: every control in this window's
chrome is drawn in the theme's ink, and a row of system checkboxes in a panel
that otherwise looks like `StyledTip` would look like a dialog. The box is a
rounded square in the separator's ink, filled in the column's colour on hover
so it reads as the thing about to be pressed, and the row's whole width is the
click target — a box eleven points wide is not a target.

The text is the step's first line as written, including the `3.2` or whatever
leads it, wrapped to two lines at the tip's width and then cut. The number is
what finds the line in the file; the continuation lines are what the file is
for. The heading is `26 open of 30`, in the title weight; the rows are in the
detail weight, at full ink rather than dimmed, since these are the thing to
read rather than a note about a control.

## Risks / Trade-offs

- **A tip that ticks a committed file on a click** → the click has to land on
  a row that names the task, inside a panel that opened only after the pointer
  rested on the card. There is no way to tick without having read the words.
  A tick is still one character in a file under git, undone in the editor.
- **A stale list ticking the wrong line** → decision 1: the line is checked
  at write time and refused if it no longer reads as that unticked step; the
  tip then reloads.
- **Two watcher reloads per tick** (the atomic write is a rename, which some
  watchers report twice) → the reload already coalesces on the main queue and
  the tip re-reads the same file twice; measured against thirty tasks that is
  nothing, and it is the same cost a terminal tick already pays.
- **The tip over the board hides cards below it** → placed under the card's
  leading edge like `StyledTip`, bounded to a third of the screen, and gone
  the moment the pointer leaves. Above the card instead where there is no
  room below, which is the panel's usual position at the bottom of the window.
- **A non-activating panel that takes clicks can swallow the click that was
  meant to close it** → the local monitor sees the mouse-down first and
  closes the tip when the click is outside it; the click then goes where it
  was going. This is what `CompletionPopup` does and it has held.
- **`BacklogPane.swift` at 2,606 lines** → the tip and its rows are a file of
  their own; the pane gains the two verbs and the hand-off, and nothing else.

## Open Questions

- Whether the tip should also open from the keyboard — a card selected and a
  key pressed — for whoever does not hover. Nothing selects a card on the
  board today, so this waits for that.
- Whether the list view's rows want the same tip. Not in this change; the
  board is where a card is looked at, and the list has the full title where
  the tip would go.
