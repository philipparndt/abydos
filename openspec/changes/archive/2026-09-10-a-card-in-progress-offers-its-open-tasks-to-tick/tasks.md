## 1. The checklist knows its lines, and one of them can be ticked

- [x] 1.1 `BacklogItem.OpenStep(line: Int, text: String)` and
      `openSteps(in:)` beside `remainingSteps(in:)`, over the same bullet and
      `[ ]` grammar `progress(in:)` reads, so the three cannot disagree about
      what a step is. `remainingSteps` becomes `openSteps.map(\.text)`.
- [x] 1.2 `BacklogItem.ticking(line:in:) -> String?`: the line's `[ ]` becomes
      `[x]`, every other byte kept — bullet, indentation, continuation lines,
      final newline or its absence — and `nil` when the line no longer reads
      as an unticked step.
- [x] 1.3 `BacklogItem.tick(line:)` and `OpenSpecChange.tick(line:)` write the
      result atomically to the item's file and to `tasksFile`, and throw
      naming the file when they cannot.
- [x] 1.4 Tests in `BacklogTests` and `OpenSpecChangeTests`, named as claims:
      `anOpenStepKnowsWhichLineItIsOn`, `tickingAStepChangesOneCharacter`,
      `tickingKeepsTheContinuationLinesAndTheMissingFinalNewline`,
      `theSecondOfTwoStepsWithTheSameWordsIsTheOneTicked`,
      `aLineThatIsNoLongerAnOpenStepIsRefused`,
      `aTickedTasksFileCountsOneMore`.

## 2. A card says which file its checklist came from

- [x] 2.1 `BacklogCard.checklistFile: URL` — the worktree copy's file where
      `source` is `.worktree`, the project's otherwise — and
      `OpenSpecCard.checklistFile` as `change.tasksFile`; both set on the walk,
      never while drawing.
- [x] 2.2 `BoardEntry.isInProgress` and `BoardEntry.identity` (a number, or a
      name), so the column can hand the tip an entry and the tip can key on
      it across reloads.

## 3. The tip

- [x] 3.1 `Sources/AbydosApp/Panel/TaskTip.swift`: a shared child `NSPanel` in
      `StyledTip`'s shape — borderless, non-activating, `.popUpMenu`, clear
      background, the sidebar's ground and edge, `StyledTip.delay` — with
      `ignoresMouseEvents = false`, placed under the card's leading edge or
      above it where there is no room, bounded to a third of the screen.
- [x] 3.2 The list: a heading `N open of M` in the title weight, a scrolling
      `NSTableView` of drawn rows — a rounded box in the separator's ink,
      filled in the column's colour under the pointer, and the step's first
      line in the detail font at full ink wrapped to two lines and cut. The
      whole row is the click target.
- [x] 3.3 Opening reads the file once, on the main thread, into `[OpenStep]`;
      `reload()` re-reads and redraws, and closes when the entry is no longer
      in progress. Shown for the same entry under a still pointer, it does not
      restart the delay.
- [x] 3.4 A click ticks through 1.3, then reloads. A refusal from `ticking`
      reloads without writing; a throw shows the sentence in the tip, naming
      the file.
- [x] 3.5 Staying and going: the pointer on the card or inside the tip keeps
      it; a quarter-second grace bridges the gap; local `NSEvent` monitors for
      `leftMouseDown`, `rightMouseDown` and `scrollWheel` outside the tip close
      it, as `CompletionPopup` does; a drag beginning, a menu opening and the
      window resigning key close it too.
- [x] 3.6 `writeImageForTesting(to:)` as `CompletionPopup` has, because a child
      window is invisible to a capture of the main one.

## 4. The column opens it

- [x] 4.1 One `NSTrackingArea` on `BacklogColumnView` with `mouseMoved` and
      `mouseExited`; the row under the pointer is hit-tested and its entry
      handed to `TaskTip.shared` where `isInProgress`, or the tip told the
      pointer is on nothing.
- [x] 4.2 The column's scroll, its drag source beginning, and `menu(for:)`
      being asked all close the tip first.
- [x] 4.3 `BacklogPane.reload()` calls `TaskTip.shared.reload()` after the
      walk, with the entry as it now stands, so a tick in a terminal drops a
      row from an open tip.
- [x] 4.4 `refuseDrag(of:)`'s sentence now says the tasks can be ticked on the
      card or in `tasks.md`.

## 5. Driving it

- [x] 5.1 On the pane, beside the state they read: `taskTipReportForTesting(change:)`
      and `(number:)` open the tip through the column's own hand-off and print
      the heading and the rows; `tickOpenTaskForTesting(change:index:)` and
      `(number:index:)` click the row through the tip's own handler and print
      the fraction afterwards. A card outside In progress prints its column
      and `no tip`.
- [x] 5.2 `LaunchOptions`: `--backlog-tasks <name|number>` and
      `--backlog-tick <name|number>:<n>`, parsed the way `--backlog-menu` tells
      a number from a name; `--backlog-tasks-shot <path>` writes the tip's
      PNG. The window controller only forwards.
- [x] 5.3 Drive it against a copy of this repository under the scratchpad,
      with a throwaway bundle id and defaults domain, and keep the PNG in the
      change's `images/`: the tip open on a card with thirty tasks, in both
      themes; a tick moving `4/30` to `5/30`; the last tick moving a card to
      Complete.

## 6. Specs and the record

- [x] 6.1 `openspec/specs/openspec-board/spec.md`: the drag requirement's
      reason and its scenario, as the delta says. No `.abydos/backlog/spec/*.md`
      is made untrue: that record is gone, and the `backlog` capability's
      requirements all still hold — the card still reads the worktree's copy,
      and now writes it too.
- [x] 6.2 `docs/index.html` and the README's line on the board mention that a
      card in progress lists its open tasks and ticks them.

## 7. Before finishing

- [x] 7.1 `make test` clean, in the background with its exit code logged.
- [x] 7.2 `make warnings` clean, the same way, and never alongside another
      build.
