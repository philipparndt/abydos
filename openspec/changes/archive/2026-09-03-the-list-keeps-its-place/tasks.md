## 0a. Name a row that has no id

- [x] 0a.1 `RunningSessions.Session.identity`: the tmux session and window
  while `isSeeded`, the id afterwards.
- [x] 0a.2 The order's final tie-break, the remembered places and the
  selection's lookup all use it.
- [x] 0a.3 `--claude-seeded <count>` seeds badged windows into the register,
  which no flag could do before — every session a run could make had an id,
  which is why no run ever showed this.
- [x] 0a.4 Driven: six badged windows come up in window order, hold it across
  two seconds of rebuilds with the selection on the second, and the shape log
  records one line rather than a shuffle.

## 0. Hold the order

- [x] 0.1 `RunningSessionsListView` records each session's and each project's
  place on the first reload after opening, and sorts by that place from then
  on; newcomers are recorded at the end as they arrive.
- [x] 0.2 `freezeOrderAgain()` forgets it, called when the list is opened —
  the popover is built fresh each time, the palette keeps its controller.
- [x] 0.3 `RunningSessions.Group` gains a public initialiser and `ordered(_:)`,
  so a view can hand back the same group with its sessions in another order.

## 0b. And a row that changes its id without moving

- [x] 0b.1 A row's place is inherited by tmux window as well as kept by id: the
  register seeds a badged window under a key of its own and swaps in the real
  record the moment that session speaks, so the same window's row would
  otherwise leave the middle and arrive at the end.
- [x] 0b.2 The list writes a line to `~/Library/Logs/Abydos/sessions.log`
  whenever its rows change shape, and nothing while they hold still. Three
  reports have now been answered from readings of the code; the fourth will
  have a record of what actually moved.

## 1. Re-find both highlights

- [x] 1.1 `reload` re-finds the selection by id, and clears it where the
  session it was on is gone.
- [x] 1.2 `reload` re-finds the hover from the pointer's position now, asked of
  the window rather than of the last event.

## 2. Say where the keys are

- [x] 2.1 The rows know whether they hold the keyboard, and redraw when that
  changes.
- [x] 2.2 A selected row is a filled band with the keyboard in the rows and an
  outline without it.
- [x] 2.3 ⏎ in the filter acts on the selected row, or the first shown.

## 3. Reopening

- [x] 3.1 `focusFilter()` puts the caret in the field with its text selected,
  and the palette calls it on every opening rather than relying on
  `viewDidAppear`.

## 4. Checked

- [x] 4.1 A `wait` key in the list's key instrument, so a real rebuild happens
  between two reports, and the report says what is hovered as well as what is
  selected.
- [x] 4.2 A driven run: two ↓ into the rows, then two real seconds in which a
  session sorting *before* the selected one arrives and the clock ticks. The
  selection is still on the same session, one row further down; four rows are
  drawn and the fourth is a second old. And with the keyboard sent back to the
  filter by ↑ off the top, the selected row is drawn as a ring.
- [x] 4.3 A driven run with the order held: four badged windows, then a session
  arriving at 6 s whose id sorts *before* all of them. The log reads
  `ydos:0 ydos:1 ydos:2 ydos:3 -> ydos:0 ydos:1 ydos:2 ydos:3 000000` — it
  landed at the end, nothing above it moved, and the selection stayed on
  `ydos:1`.
- [x] 4.4 `make test` and `make warnings`, both clean by their exit codes.
  4023 tests in 512 suites, exit 0, at load 25 over 14 cores on 2026-09-03; `make warnings` exit 0. Two wall-clock classifications were replaced to get there — see `a-deadline-is-named-not-timed`.
