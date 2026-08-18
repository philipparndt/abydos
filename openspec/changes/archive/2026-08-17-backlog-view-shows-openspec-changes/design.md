## Context

`BacklogPane` is two presentations of one directory — a list for reading and a
board for moving — and neither holds state of its own: `reload()` walks
`.abydos/backlog` off the main thread, builds a `BacklogCard` per item, and hands
the main thread five fields per card because `draw(_:)` runs on every scroll. A
`FileSystemWatcher` on the backlog directory keeps it honest when somebody moves a
file in a terminal. That arrangement is the thing to preserve; what has to give is
the assumption that the only thing on the board is a `BacklogItem`.

### What an OpenSpec change is, on disk

    openspec/
      config.yaml                     schema: spec-driven
      specs/                          (empty here)
      changes/
        archive/
        completions-say-what-goes-in-them/
          .openspec.yaml              schema: spec-driven / created: 2026-08-17
          proposal.md
          design.md
          specs/<capability>/spec.md
          tasks.md                    "- [ ] 1.1 …", 30 of them

Eight changes are in this repository today, 11 to 30 tasks each. Counting
`- [ ]` and `- [x]` at the start of a line with `grep -c` gives the same totals
the CLI reports for every one of them, so the fraction on a card does not need a
subprocess to be right.

### What the CLI adds, and what it costs

`openspec list --json` gives `{name, completedTasks, totalTasks, lastModified,
status}` per change. `openspec status --change <name> --json` gives per-artifact
`done` / `ready` / `blocked` plus `applyRequires` — which artifacts must exist
before implementation can start, and that comes from the *schema*, which lives
inside the CLI rather than in the project.

Measured here: 0.60 s wall for `list --json`, 0.60 s for one `status --change`.
Node start-up, not work. Eight changes through `status` is about five seconds,
and the pane reloads on every FSEvent under the watched directory — including the
ones an agent ticking a checkbox produces.

And the copy on this machine is:

    /Users/philipparndt/.local/state/fnm_multishells/91100_1786908065368/bin/openspec
      -> ../lib/node_modules/@fission-ai/openspec/bin/openspec.js

An fnm multishell directory, with a shell's PID in its name. `Executables.swift`
already records what a Dock-launched Abydos has for a `PATH` —
`/usr/bin:/bin:/usr/sbin:/sbin`, measured with `ps eww` — so this path is
invisible unless the login shell is asked, and it is not a path worth
remembering between launches either.

## Goals / Non-Goals

**Goals:**

- The pane answers "what is left to do" for a project that keeps its work in
  `openspec/`, with the same board and the same list.
- A change is readable with nothing installed: markdown and a two-key header.
- What a card can and cannot do matches what the thing behind it is. A derived
  state is not draggable.
- One checklist parser, so a fraction means the same thing on both kinds of card.

**Non-Goals:**

- Starting an agent on a change. `abydos-backlog start` makes a worktree and
  records a `BacklogRun` keyed by the item's *number*; a change has a name and no
  number, and `/opsx:apply` is a slash command rather than a binary. Worth doing
  and worth doing on its own.
- Writing changes from the pane — `new`, `archive`, moving artifacts along. The
  first pass reads and opens.
- Merging the two into one list. They are different shapes; see the table in the
  proposal.
- Migrating the backlog into OpenSpec, or the reverse. Both are live here on
  purpose.

## Decisions

**The board reads the directory; the CLI is not on the drawing path.** Ruled out:

- *The CLI as the source of truth.* Five seconds per reload, on a pane that
  reloads whenever an agent ticks a box, and nothing at all on a machine where
  the CLI is not installed or is behind a version manager the app cannot see. A
  project's changes are committed files; a teammate without Node still has them.
- *A hybrid where `list --json` is called once per reload.* One process instead of
  eight, but it still costs 0.6 s and still shows nothing without Node, and it
  buys only what a directory walk already gives.

What the CLI is genuinely authoritative about is `applyRequires` — which artifacts
the schema demands — because that lives in the CLI, not in the project.
**Open:** whether to hard-code the `spec-driven` answer (`tasks`), which is a
drift risk, or to ask the CLI once when it happens to be there and fall back.
Leaning: derive the column from what is *present* rather than from what is
*required* — a change with `tasks.md` and ticked boxes is in progress whatever the
schema thinks — and keep the schema question out of the first pass entirely.

**The column a change lands in is derived, and the derivation is the spec.**

| column | when |
| --- | --- |
| Open | no `tasks.md` yet — still being written |
| Ready | `tasks.md` with nothing ticked |
| In progress | some ticked, some not |
| Completed | every task ticked |

`waiting` is left empty for changes: nothing on disk says a change is stuck on
something, and inventing a marker for it would be a format this project made up.

**The archive is not a column.** `changes/archive/` is exactly `history`'s
argument — the board's comment already says why a 390-record column beside four
short ones is a wall rather than a board. Archived changes belong in the list.

**A change's card does not drag.** The backlog's drag is an `mv` and the state is
the folder; a change's state is read out of its files, so dragging could only mean
"tick or untick somebody's checkboxes", which is not a thing a drag should do.
Ruled out: making the drag work by editing `tasks.md` — a gesture that rewrites a
file nobody opened is the kind of thing that gets discovered by accident and
distrusted afterwards. The card refuses and says why once, rather than being inert.

**Where the switch between the two sources lives.** Options weighed:

- *A second button on the left rail.* Ruled out: two buttons that both mean "what
  is left to do" is the confusion this change is supposed to remove.
- *One board with both kinds of card in the same columns.* Ruled out for the first
  pass: `ready` means "a person has agreed this is decided" in the backlog and
  "the artifacts are written" in OpenSpec, and stacking the two under one heading
  quietly redefines the backlog's most carefully argued folder.
- *A source control in the pane's header, beside the existing list/board toggle.*
  Chosen. It appears only when the project has both, and it is orthogonal to
  list/board — the two questions are "which record" and "which presentation", and
  neither answers the other.

**One checklist parser.** `BacklogItem.progress()` counts ticks under `## Steps`;
a change's tasks are the same checkboxes under numbered headings. The counting
moves somewhere both can call, and both keep returning `BacklogItem.Progress`,
which is already what the card draws. Ruled out: a second `Progress` type — two
fractions that mean the same thing and can disagree about the empty case is
exactly the sort of pair this codebase gets rid of on sight.

**Reading is `AbydosKit`, drawing is `AbydosApp`.** The `.openspec.yaml` header
has two keys and is read as two lines rather than by adding a YAML dependency;
if it ever grows something structural that decision gets revisited with a reason
written down.

**Cost, because this is the same reload path.** A change is one directory read
plus one file read for `tasks.md`; the artifact list is the directory entries
already in hand. That is cheaper per card than a backlog item, which costs four
reads. It runs on the same background walk, and nothing is asked again while
drawing.

## Risks / Trade-offs

- **Two dashboards drift.** Two sources in one pane means two sets of rules for
  what a column means → the derivation table above is in the spec, so a change to
  it is a change somebody reviews.
- **The `openspec` format is somebody else's and can move.** `.openspec.yaml`,
  `tasks.md`, `specs/<name>/spec.md` are conventions of a tool at version 1.3.1 →
  the reader is one type in AbydosKit with fixture tests, so a format change is
  one file and a red test rather than a hunt.
- **A change with no `tasks.md` looks abandoned rather than early.** It lands in
  Open, which is right, but the card has no fraction to show → the card says which
  artifacts exist instead, which is the useful thing at that stage anyway.
- **Doing nothing about starting work on a change.** The pane will show eight
  changes and offer no way to pick one up, which invites the question → the
  non-goal is stated, and opening the artifacts is what a person does next.
- **The list gets long.** Eight changes plus an archive plus forty backlog items →
  the source switch means only one of them is ever on screen.

## Open Questions

- Hard-code `spec-driven`'s `applyRequires`, ask the CLI when present, or avoid
  the question by deriving from what exists? Leaning towards the third.
- Does a change's card want its artifact list — four small marks for proposal,
  design, specs, tasks — or is the fraction enough? The artifacts are the
  interesting part before any task is ticked and clutter afterwards.
- Where do `openspec/specs/` capabilities show up, if anywhere? Empty in this
  project, so nothing to look at yet.
- Should the source switch remember its position per project, the way the
  list/board mode does?
