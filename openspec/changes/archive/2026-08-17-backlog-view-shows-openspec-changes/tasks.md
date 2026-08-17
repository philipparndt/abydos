## 1. Reading a change, in the engine

- [x] 1.1 New file beside `Sources/AbydosKit/Backlog` — no view code — with the
      type for a change: name, directory, the artifacts present, whether it is
      archived, and the two keys from `.openspec.yaml` read as lines.
- [x] 1.2 Find changes: every directory under `openspec/changes/` except
      `archive/`, and every directory under `archive/` marked archived.
- [x] 1.3 Derive the state — no `tasks.md`, nothing ticked, part ticked, all
      ticked — and never `waiting`. The table in `design.md` is the spec.
- [x] 1.4 One parser for both. Nothing had to move: `BacklogItem.progress(in:)` was
      already a static over any markdown, so `OpenSpecChange.progress()` calls it
      and its comment now says it answers for both. A change with no `tasks.md`
      has no progress rather than `0/0`.
- [x] 1.5 Whether a project has OpenSpec at all — `openspec/changes` exists — as
      the counterpart of `Backlog.exists`.

## 2. Tests for the reading

- [x] 2.1 Fixture directories under `Tests`, named as claims:
      `aChangeWithNoTasksFileIsStillBeingWritten`,
      `aChangeWithEveryTaskTickedIsDone`,
      `anArchivedChangeIsNotOnTheBoard`,
      `aChangeWithNoHeaderIsStillAChange`.
- [x] 2.2 The counting is the same for both: a test that a `## Steps` checklist
      and a `tasks.md` with the same ticks give the same fraction.
- [x] 2.3 A test that reading a project's changes starts no process — the point of
      1.1, and the thing that would quietly regress.

## 3. The pane takes a second source

- [x] 3.1 A source control in the header, shown only where the project has both,
      orthogonal to the list/board toggle. Decide whether it is remembered per
      project (design, open question) and say which and why.
- [x] 3.2 Generalise `cardsByState` and `refreshViews` so a column can hold either
      kind of card without the board learning about both.
- [x] 3.3 A card for a change: its name, its fraction, and — before any task is
      ticked — which artifacts exist.
- [x] 3.4 Read the changes on the same background walk as the backlog, once, with
      nothing asked again while drawing. Say in the comment what a change costs
      against the four reads an item costs.
- [x] 3.5 Watch `openspec/changes` the way the backlog is watched, so a box ticked
      in a worktree moves the card.

## 4. What a card does

- [x] 4.1 Opening a card reaches its artifacts in the editor — `proposal.md`,
      `design.md`, `tasks.md`, each `specs/<capability>/spec.md`.
- [x] 4.2 Refuse the drag, and say why once rather than the card being inert.
      Check the backlog's own drag still works in the same pane.
- [x] 4.3 The archive is in the list and not on the board.

## 5. The CLI, only where it writes

- [x] 5.1 Locate `openspec` through `Executables.locate`, which asks the login
      shell — the installed copy here is under an fnm multishell path with a PID
      in its name.
- [x] 5.2 Say what is missing, and how to install it, where a verb needs the CLI
      and it is not there. Nothing that only reads the directory depends on it.
      **The verb turned out to be a smaller thing than the design assumed.**
      Writing changes from the pane is a stated non-goal, so there was nothing
      for the locator to serve — and building an unused locator would have been
      worse than not having one. A finished change's menu offers the
      `openspec archive <name>` command to *copy* instead, which needs the tool
      to be found and says so when it is not, without the pane rewriting a
      project's specs from a menu.

## 6. Finishing

- [x] 6.1 `.abydos/backlog/spec/backlog.md`: "The backlog has a button on the left
      rail" becomes a pane with two sources, and "An item's state is the folder it
      is in" gains its counterpart — a change's state is derived, and therefore
      not draggable. Nothing else in that file is made untrue.
- [x] 6.2 Driven by hand against a copy of this repository under the scratchpad,
      never a real checkout: both sources, the board for each, a box ticked in a
      terminal moving a card, and a drag refused. Pictures for the item.
- [x] 6.3 `make test` clean.
- [x] 6.4 `make warnings` clean.

## 7. What the driving showed

- [x] 7.1 `--backlog openspec` and `--backlog openspec-list` pick the record, and
      `--backlog openspec-watch` prints the board again twelve seconds later so
      that "a box ticked in a terminal moves the card" is something somebody can
      watch rather than something the code claims. Driven against a scratchpad
      copy: `capture-flags-work-alone` went from `ready 0/11` to
      `in-progress 1/11` with nothing clicked.
- [x] 7.2 The board read this repository's own changes correctly on the first
      run, `completions-say-what-goes-in-them` included at 33/33 in Completed —
      the change finished an hour earlier, which is as good a check of the
      derivation as a fixture.
