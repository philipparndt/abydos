## Why

**A box that only a person can tick has to be ticked in a file.** Half the
tasks a change ends with are ones a suite cannot prove — *photograph the board
at five columns*, *check the tip reads in the dark theme*, *drive a run and
read what it says* — and what proves them is somebody watching the app. That
somebody is looking at the board when they are satisfied, and the board shows
them `26/30` on a card and nothing else. To say *that one is done* they open
`tasks.md`, find the line among thirty, and edit `[ ]` to `[x]` by hand; or
they right-click the card and copy `complete <name>, I have verified it`, which
ticks every box at once through an assistant, including the ones they did not
look at.

Neither is the gesture being asked for. The card in progress should say what is
still open, on the pointer resting on it, and each open task should be tickable
where it is read — the way a manual-verification list is worked: look, confirm,
tick, next. The fraction on the card, the bar under it and the column it sits
in already follow the file; this is only the other direction.

The same is true of a backlog item's `## Steps`, which is the same checklist
under a different heading and is counted by the same function. A card for
either record, in progress, gets the same tip.

No originating backlog item: the backlog was dropped on 2026-08-19 and this was
asked for on 2026-09-08. The nearest prior work is the change that gave a
part-way card its three sentences (`openspec-board`, *A card offers the command
that starts work on it*), whose second sentence is the all-at-once version of
what this does one task at a time, by hand, with no assistant in the loop.

## What Changes

- **A task tip on a card in progress.** When the pointer rests on a card in
  the In progress column — a change with some tasks ticked, or an item in
  `in-progress/` — a panel opens under it listing the tasks still open, each
  with a box, headed by how many are open of how many. It appears after the
  same wait the app's own tooltip uses and in the same type and ground.
- **The boxes tick.** A click on a box rewrites that one line of the file from
  `- [ ]` to `- [x]`, atomically, and nothing else in the file changes. The
  board notices the write the way it notices an agent's, so the fraction, the
  bar and the column follow; the tip drops the row. Ticking the last open task
  moves the card to Complete and closes the tip, since there is nothing left
  to list.
- **The file ticked is the one the fraction came from.** For an item being
  worked in a worktree that is the worktree's copy, as `backlog` says the card
  reads; for a change it is the change's own `tasks.md`.
- **Unlike the app's tooltip, this one takes the pointer.** The drawn tooltip
  ignores the mouse on purpose; a list of boxes cannot. The tip stays while the
  pointer is on the card or inside the tip, and goes when it leaves both, on a
  click anywhere else, on a scroll, or when a drag or a menu starts.
- **Not proposed: unticking.** A ticked task is not listed, so there is nothing
  to untick. Undoing a tick is a one-character edit in the file, and a tip that
  offered both directions would be a checklist editor, not a tip.
- **Not proposed: the tip on a Ready card.** Ticking the first box on a change
  is what moves it to In progress, and that is an agent picking work up, not a
  person confirming it. A card nobody has started has nothing verified.
- **A driven run reads and ticks.** Two verbs on the pane, declared beside the
  state they drive as `screenshots` requires: one hovers a named card and
  prints what the tip lists, one ticks the n-th open task through the tip's
  own action and prints the fraction afterwards. A child window is invisible
  to a capture of the main one, so the tip draws itself to a PNG on request,
  as the completion popup does.

## Capabilities

### New Capabilities

- `open-tasks-on-a-card`: what the tip on a card in progress shows, when it
  appears and goes, what a click on a box writes and to which file, and what a
  driven run can read and do.

### Modified Capabilities

- `openspec-board`: *A change cannot be dragged between columns* says a drag
  is refused because it "could only mean rewriting checkboxes nobody opened",
  and the refusal tells the person to tick them in `tasks.md`. Both stay true;
  the refusal SHALL now also point at the tip, and the requirement says why a
  box ticked by name on a card is not the rewrite a drag would be.

## Impact

- `Sources/AbydosKit/Backlog/BacklogItem.swift`: the open steps gain their
  line numbers, and a pure function over markdown ticks one of them. No view
  code; the writes are tested without a window.
- `Sources/AbydosKit/OpenSpec/OpenSpecChange.swift` and `BacklogCard`: each
  card says which file its checklist was read from, so the tip writes the copy
  the fraction came from.
- `Sources/AbydosApp/Panel/`: a new `TaskTip` — a child panel that takes the
  mouse, in `StyledTip`'s shape and type — and the hover tracking on
  `BacklogColumnView` that opens it. `BacklogPane.swift` is at 2,606 lines;
  the tip is a file of its own.
- `LaunchOptions` and the pane gain the two driving verbs.
- `openspec/specs/openspec-board/spec.md`, one requirement's reason.
- No new dependency. `StyledTip` is unchanged and still ignores the mouse.
