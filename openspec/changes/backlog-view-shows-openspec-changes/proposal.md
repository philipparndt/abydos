## Why

This project has two records of what is left to do and the app shows one of them.
`.abydos/backlog` has its board on the left rail; `openspec/changes/` has eight
changes in it — 11 to 30 tasks each, several of them written this afternoon — and
nothing in the window knows they exist. The pane that exists to answer "what is
left" answers half of it, and the half it leaves out is the half being written.

The two are not the same shape, which is why this is not a rename:

|  | backlog | OpenSpec |
| --- | --- | --- |
| an item is | `0540-find-match-bands-…md`, numbered | `completions-say-what-goes-in-them/`, named |
| its state is | the folder it sits in, moved with `git mv` | derived — which artifacts exist, how many tasks are ticked |
| its progress is | a `## Steps` checklist | `- [ ] 1.1` checkboxes in `tasks.md` |
| picking it up | `abydos-backlog start`, a worktree, an agent | `/opsx:apply <name>` |
| finishing | the file moves to `completed/` | `openspec archive` moves it to `changes/archive/` |

`BacklogPane` is bound to the first of those at every level: `cardsByState:
[BacklogState: [BacklogCard]]`, `backlog.items(in: state)`,
`FileSystemWatcher(root: backlog.directory)`, and a drag that is an `mv` between
two of those folders. None of that is wrong; it is just the only thing it can do.

**And the state a change is in cannot be dragged.** A backlog card moves between
columns because moving the file *is* the change of state. An OpenSpec change's
column is worked out from what is in its directory, so a card that could be
dragged would be a card that lies. That difference has to be visible in the design
rather than discovered by somebody dragging one.

From a direct request rather than a backlog item. Related: `.abydos/backlog` and
`openspec/` are both live in this repository on purpose — nothing has been moved
out of the backlog — so this adds a second source to the pane rather than
replacing the first.

## What Changes

- **The backlog pane reads `openspec/changes/` as well as `.abydos/backlog`.** A
  project with both offers both; a project with one shows that one with no switch
  to a source it does not have.
- **A change is read from the directory, not from the `openspec` CLI.** Measured on
  this machine, `openspec list --json` costs 0.60 s and `openspec status --change`
  another 0.60 s per change — Node start-up, paid eight times over on a pane that
  reloads on every FSEvent. Worse, the installed `openspec` is at
  `~/.local/state/fnm_multishells/91100_1786908065368/bin/openspec`: an fnm
  directory with a shell's PID in its name, invisible to an app whose `PATH` is
  the four directories a Dock launch inherits.
- **A change gets a column worked out from what is on disk**: artifacts still
  missing, ready to apply, tasks part-done, tasks all done. The columns are the
  ones already on the board.
- **A change's card says its fraction** the way an item's does — the same
  `- [ ]`/`- [x]` counting, against `tasks.md` rather than `## Steps`.
- **A card opens its artifacts.** `proposal.md`, `design.md`, `tasks.md` and each
  `specs/<capability>/spec.md`, in the editor, which is what a change is for.
- **A change cannot be dragged between columns**, and the board says why rather
  than silently refusing.
- **The archive is not a column.** `changes/archive/` is `history`'s shape — a wall
  beside four short columns — and it is reachable from the list instead.
- **Where the `openspec` CLI is wanted for something that writes** — `archive`,
  `validate` — it is found through `Executables.locate`, which asks the login
  shell, and its absence is a sentence rather than nothing happening.

## Capabilities

### New Capabilities

- `openspec-board`: what the pane shows for a project with an `openspec/`
  directory — which changes appear, which column each lands in, what its card
  says, and what a card does when it is opened or dragged.
- `openspec-reading`: how a change is read off the disk — artifacts, task
  progress, archived changes — without the `openspec` CLI being installed.

### Modified Capabilities

<!-- None in openspec/specs/, which is empty. In .abydos/backlog/spec/backlog.md
     the requirement "The backlog has a button on the left rail" becomes a pane
     with two sources rather than one, and "An item's state is the folder it is
     in" gains its counterpart: a change's state is derived, and therefore not
     draggable. -->

## Impact

- `Sources/AbydosApp/Panel/BacklogPane.swift` — `cardsByState`, `reload`, `watch`,
  the mode control, `BacklogCard`, and the drag that assumes an `mv`.
- New in `Sources/AbydosKit` — the reading of a change is engine work and belongs
  where it can be tested without a window, beside `Sources/AbydosKit/Backlog`.
- `BacklogItem.progress()` parses a checklist under `## Steps`; the counting is the
  same and wants one parser rather than two.
- `Sources/AbydosKit/Support/Executables.swift` — already the answer for a tool a
  version manager owns, and `openspec` is exactly that case.
- `.abydos/backlog/spec/backlog.md`.
- No new dependency: the format is markdown files and one small YAML header
  (`schema:`, `created:`) which does not need a YAML parser to read two keys.
