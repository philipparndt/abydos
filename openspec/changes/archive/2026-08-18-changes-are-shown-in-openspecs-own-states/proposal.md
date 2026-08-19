## Why

The pane shows OpenSpec changes in the backlog's five folders — open, ready,
in-progress, waiting, completed — because that is what the board already had.
**OpenSpec has states of its own, and they are not those.** Measured against the
installed CLI rather than guessed at, there are three vocabularies at three
levels:

| asked | answers |
| --- | --- |
| `openspec list --json` | `no-tasks`, `in-progress`, `complete` |
| `openspec status --change X --json` | per artifact: `done`, `ready`, `blocked` |
| `openspec instructions apply` | `blocked`, `ready`, `all_done` |

None of them is the backlog's, and the mapping invented for the first pass
disagrees with all three in a way somebody will act on: a change with a
`tasks.md` and nothing ticked is shown as **ready**, and `openspec list` calls
the same change **in-progress**. Two answers to "what is this change doing", one
of them made up here.

**And the archive is where every finished change goes.** Nine of them, and the
board shows an empty five columns — because archived changes were kept off it by
borrowing `history`'s argument from the backlog. That argument does not hold: the
backlog's `completed/` keeps finished items for ever and `history` is 390 records
from before the backlog existed, while OpenSpec has no `completed/` at all. A
change moves to `changes/archive/` the moment it is done, so the archive *is* the
completed column. The list does show them, which is why this reads as "sometimes
they are there and sometimes they are not" rather than as a missing feature.

Reported after a day in which nine changes were archived and the board went
blank. From `.abydos/backlog/spec/backlog.md`, whose requirement "A change's
state is derived" this makes more specific rather than untrue.

## What Changes

- **The board's columns for OpenSpec become OpenSpec's own lifecycle**, not the
  backlog's folders: what is still being written, what can be picked up, what is
  under way, what is finished, what is archived. The backlog keeps its five, and
  that is the point of two sources.
- **The archive is a column**, because it is where finished work lives. The
  backlog's `history` argument was borrowed and does not apply.
- **A change with tasks and nothing ticked stops being called "ready"** where
  OpenSpec calls it in-progress, or the disagreement is stated on the card. One
  of the two, decided in `design.md`, not both.
- **What is missing is named while a change is being written.** OpenSpec knows
  which artifact is `blocked` and on what; the card says "needs tasks" rather
  than sitting silently in a column called Open.
- **Progress stays as it is.** The `- [x]`/`- [ ]` counting already agrees with
  `completedTasks`/`totalTasks` for every change in this repository — checked
  yesterday, and again here — so nothing about the fraction changes.
- **A card offers the command that starts work on it.** A finished change already
  offers `openspec archive <name>` to copy; a change waiting to be picked up
  offers nothing, which is the more useful of the two. **There is no `openspec
  apply`** — the CLI has `init`, `list`, `archive`, `validate`, `show`, `status`
  and the rest, and applying is `openspec instructions apply --change <name>`
  feeding an agent. So what a card offers is `/opsx:apply <name>`, the slash
  command that does it, and it is offered only where the change can actually be
  picked up.
- **Not proposed: running the CLI to find out.** 0.60 s per invocation and an
  fnm path a Dock-launched app cannot see; the reasons are in the archived
  `backlog-view-shows-openspec-changes` and they still hold.

## Capabilities

### New Capabilities
<!-- None. -->

### Modified Capabilities

- `openspec-board`: which columns a change can be in, that the archive is one of
  them, and what a card offers to copy. The requirement "A change's state is
  derived, and therefore not draggable" keeps its second half exactly and has its
  first half replaced: the derivation is of OpenSpec's states rather than of the
  backlog's. The command a card offers belongs here because *which* command it
  offers follows from the state it is in, which is what this change is about.
- `openspec-reading`: what a change's state is called, and that a change
  declaring a schema this reader does not know says so rather than being sorted
  by a guess.

## Impact

- `Sources/AbydosKit/OpenSpec/OpenSpecChange.swift` — `state(progress:)` returns
  `BacklogState` today, which is what forces the backlog's vocabulary on it.
- `Sources/AbydosApp/Panel/BacklogPane.swift` — the board is `BacklogState.board`
  for both sources; the columns have to come from whichever source is showing.
  `BoardEntry`, `entries(in:)`, the list's sections and the summary line.
- `.abydos/backlog/spec/backlog.md`.
- **The schema question, which the first pass deliberately left alone.** States
  derived from files are the right answer for `spec-driven`, whose
  `applyRequires` is `[tasks]` and whose `tasks` requires `specs` and `design`
  which require `proposal` — so "tasks.md exists" implies the chain. A change
  declaring another schema is the case that must not be answered with a guess.
- No new dependency, and nothing new on the drawing path.
