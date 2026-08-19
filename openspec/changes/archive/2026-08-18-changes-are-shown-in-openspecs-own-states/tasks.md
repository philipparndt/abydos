## 1. The states, in the engine

- [x] 1.1 A state of OpenSpec's own on `OpenSpecChange`, replacing the
      `BacklogState` it answers in today — writing, ready, in progress, complete,
      archived — with the apply vocabulary named in the comment beside it.
- [x] 1.2 Which artifact is next, from the per-artifact `done`/`ready`/`blocked`
      that `spec-driven`'s `requires` chain implies. That is what a card says
      while a change is being written.
- [x] 1.3 A change declaring a schema other than `spec-driven` is answered as
      unknown rather than placed. A missing header stays `spec-driven`.
- [x] 1.4 Tests as claims, against the five stages measured in `design.md`:
      `aChangeWithNothingTickedIsReadyRatherThanInProgress`,
      `aChangeStillBeingWrittenSaysWhatItNeedsNext`,
      `anArchivedChangeIsInItsOwnState`,
      `aChangeWithAnUnknownSchemaIsNotSorted`.
- [x] 1.5 A test that the fraction still agrees with `completedTasks` /
      `totalTasks` for this repository's own archived changes — the one thing
      that is already right and must stay so.

## 2. The board takes its columns from the source

- [x] 2.1 Columns become a property of whichever record is showing, rather than
      `BacklogState.board` for both.
- [x] 2.2 The backlog's five are untouched — checked by driving it, not by
      reading the diff.
- [x] 2.3 Archived is a column for OpenSpec, last, after Complete.
- [x] 2.4 The summary line counts the columns that exist for the source showing.
- [x] 2.5 The drag is still refused, and still says why.

## 3. The card

- [x] 3.1 A change being written says what is written and what is needed next.
- [x] 3.2 A change with an unknown schema says so.
- [x] 3.3 The fraction is unchanged.

## 4. The apply command

- [x] 4.1 `OpenSpecChange.applyCommand(for:)` beside `archiveCommand(for:)`,
      returning `/opsx:apply <name>`, with a test that it is exactly that.
- [x] 4.2 It answers nil where the change cannot be picked up — Writing,
      Complete, Archived — and non-nil for Ready and In progress, tested at all
      five states off the sandbox in `design.md`.
- [x] 4.3 The card's menu offers it, above the archive entry where a change has
      both — it never does, but the order is fixed rather than incidental.
- [x] 4.4 No `Executables.locate` on this path. Assert it: the entry is offered
      with `PATH` holding no `openspec`, which is the Dock case.

## 5. Watched

- [x] 5.1 Driven against a scratchpad copy of this repository, never the
      checkout: nine archived changes and no active ones, and the board shows the
      nine rather than five empty columns.
- [x] 5.2 A change at each of the five states on one board, from the sandbox in
      `design.md`, with a picture, and the menu opened on a Ready one in it.
- [x] 5.3 The backlog source photographed beside it, five columns as before.

## 6. Finish

- [x] 6.1 `.abydos/backlog/spec/backlog.md`: the derivation table is replaced and
      the archive stops being excluded. Say which sentences this makes untrue —
      the `history` argument quoted there is one of them.
- [x] 6.2 `make test` and `make warnings` both clean, and their exit codes now
      mean it.
- [x] 6.3 Write down what was ruled out, including reading the schema YAML out of
      the CLI's package directory and why the fnm path killed it.
