## Context

What the pane does now: `OpenSpecChange.state(progress:)` returns a
`BacklogState`, so a change is sorted into the folders an item lives in. The
board is `BacklogState.board` for both sources, and archived changes are kept off
it deliberately, with `history`'s argument quoted.

What OpenSpec says about the same change, measured against the installed CLI in a
sandbox built for the purpose — five changes, one at each stage:

    only-proposal    list: no-tasks     artifacts: proposal done, specs/design ready, tasks blocked
    has-specs        list: no-tasks     artifacts: proposal/specs/design done, tasks ready
    ready-to-apply   list: in-progress  artifacts: all done   apply: ready      0/2
    part-done        list: in-progress  artifacts: all done   apply: ready      1/2
    all-done         list: complete     artifacts: all done   apply: all_done   2/2

Three things fall out of that table.

**`isComplete` does not mean finished.** It means every artifact `apply.requires`
exists — `ready-to-apply` has it with nothing ticked. A reader who takes it for
"done" gets the opposite of the truth.

**`openspec list` collapses two states this board wants apart.** Nothing ticked
and half ticked are both `in-progress` to it, because it only counts tasks. The
distinction between "nobody has started" and "somebody is in the middle of it" is
most of what a board is *for*.

**And the archive is the completed state.** OpenSpec has no `completed/`; a
change goes to `changes/archive/<date>-<name>` the moment `openspec archive` runs.
The backlog's `history` is 390 records from before the backlog existed and is
excluded from its board for that reason; borrowing the argument put every finished
change out of sight, which is the report.

## Goals / Non-Goals

**Goals:**

- A change is shown in a state OpenSpec would recognise, named as OpenSpec names
  it.
- Finished work is visible.
- What a change is waiting for, while it is being written, is on the card.
- The backlog keeps its own five columns, unchanged.

**Non-Goals:**

- Running the CLI to find any of this out. 0.60 s an invocation, on a pane that
  re-reads whenever an agent ticks a box, and an fnm path a Dock-launched app
  cannot see. The archived `backlog-view-shows-openspec-changes` argues it and
  the argument holds.
- Implementing OpenSpec's schema engine. See the decision below for how far this
  goes and where it stops.
- Editing changes from the pane. Still out; still `openspec`'s.

## Decisions

**The apply state is the spine, because it is the question a board answers.**
Three candidates, and the choice is about which question the columns ask:

- *`openspec list`'s three* (`no-tasks`, `in-progress`, `complete`) — the
  shallowest, and it merges "ready to pick up" with "half done", which is the
  distinction somebody scans a board for.
- *The per-artifact three* (`done`, `ready`, `blocked`) — four artifacts each, so
  it is a state per document rather than per change; it belongs **on the card**,
  not as columns.
- *The apply three* (`blocked`, `ready`, `all_done`) — exactly "can this be
  picked up", which is what `ready` means in the backlog too, so the two sources
  stay legible side by side. Chosen.

So the columns are **Writing** (apply blocked — artifacts missing), **Ready**
(apply ready, nothing ticked), **In progress** (some ticked), **Complete** (all
ticked, not archived), **Archived**.

Ready and In progress are one state to `openspec list`. **The board disagrees
with the CLI there on purpose, and says so in the code**: the CLI is answering
"has work started" from a task count, and a board is answering "what can I pick
up". Both are `in-progress` if anybody asks the CLI, and nothing here reports a
different answer to anything but the eye.

**Archived is a column, and its argument is the opposite of `history`'s.** The
backlog excludes `history` because it is 390 records of what happened before, and
`completed/` is on the board. OpenSpec has no `completed/`, so excluding the
archive excluded every finished change. It goes last, after Complete, where
`completed` is on the other board.

**`OpenSpecChange` stops answering in `BacklogState`.** That type is the
backlog's folders, and returning it is what forced this. It gains a state of its
own; the pane maps a *source* to the columns it has, rather than assuming five.

**The schema question, answered as narrowly as it can be.** `spec-driven`'s
`apply.requires` is `[tasks]`, and `tasks` requires `specs` and `design`, which
require `proposal` — so "tasks.md exists" implies the whole chain, and every state
above is computable from the files. That is what makes this affordable, and it is
true for exactly one schema.

A change carries `schema:` in its `.openspec.yaml`. Where it is not
`spec-driven`, the reader **says so and does not sort it**: it goes to Writing
with "unknown schema" on the card, rather than being placed by a rule that does
not apply to it. Reading the schema YAML out of the CLI's package directory was
considered and refused — it is under an fnm path with a Node version in it, it is
that package's private layout, and it would put a per-machine dependency on the
drawing path this change is otherwise keeping clear.

**What a change is waiting for goes on the card.** The per-artifact states say
which document is missing and which is next, which is the useful thing while
something is being written — "needs tasks" rather than a silent card in a column.

**Cost is unchanged.** The same directory listing and the same one file read. No
new work per card, nothing asked again while drawing.

**The command a card offers follows from its state, which is why it belongs
here.** A finished change already offers `openspec archive <name>` to copy. A
change waiting to be picked up offers nothing, and that is the one somebody wants
most:

    /opsx:apply changes-are-shown-in-openspecs-own-states

**Not `openspec apply`, because there is no such verb.** The CLI has `init`,
`update`, `list`, `view`, `change`, `archive`, `spec`, `config`, `schema`,
`validate`, `show`, `status` and `instructions` — checked, not assumed. Applying
is `openspec instructions apply --change <name>` printing what to do, and then an
agent doing it. The thing a person actually pastes is the slash command, which
lives in `.claude/commands/opsx/apply.md` and is committed to this repository, so
it is there whenever the repository is.

**And it is a different kind of thing from the archive entry**, which the menu
must not blur. `openspec archive <name>` goes into a terminal and needs the CLI
found — hence `Executables.locate` and the entry that says so when it is missing.
`/opsx:apply <name>` goes into an assistant and needs no CLI at all; an
installed-or-not check on it would be answering a question nobody asked. Two
commands, two homes, and the menu says which is which rather than offering a
column of look-alike lines.

**Offered only where it can be acted on**, which the new states make expressible:
a change in **Ready** or **In progress** can be picked up, so it offers the
command. **Writing** cannot — `apply` is blocked until the artifacts exist, and
`openspec instructions apply` says so itself with `state: blocked`. **Complete**
and **Archived** have nothing left to apply, and Complete already has the archive
command to offer. Offering apply everywhere would be a menu entry that produces a
command an agent refuses, which is worse than no entry.

## Risks / Trade-offs

- **Two sources with different columns.** The board has assumed one set. →
  Columns become a property of the source; the drag refusal and the archive
  section are already source-dependent, so this is the same seam widened.
- **Disagreeing with `openspec list` about "ready".** Somebody comparing the pane
  with the CLI will see it. → Said in the code and in the spec, with the reason;
  and the fraction on the card is the same number the CLI reports either way.
- **The archive only grows.** Nine today, hundreds in a year, and then it is
  `history`'s problem after all. → Say the threshold now rather than discover it:
  when the archive column is longer than the board is tall it wants collapsing or
  a date cut, and that is a separate item with a real number behind it.
- **A schema this reader does not know.** → Named, not guessed. A card that says
  "unknown schema" is a card somebody can act on; a card sorted by the wrong rule
  is not.

## What was ruled out

Written while doing it, so the reasons are the ones that actually applied rather
than the ones that sound best afterwards.

**Reading the schema out of the CLI's own package directory**, which would have
made every schema's states readable rather than one. It is under
`~/.local/state/fnm_multishells/91100_1786908065368/…`, an fnm path with a shell
PID in it; it is that package's private layout, which nothing promises to keep;
and it would put a per-machine dependency on the one path this change is
otherwise keeping clear of one. A change in an unknown schema is named instead —
`unknown schema: lean-change` on the card — which somebody can act on.

**Running `openspec status --change` per change to get the artifact states**
rather than deriving them. 0.60 s of Node start-up each, on a pane that re-reads
whenever an agent ticks a box. Already argued in the archived
`backlog-view-shows-openspec-changes`, and the argument is unchanged. The one
place a subprocess is now spawned is a *test* — `theFractionIsTheNumberTheCLIReports`
runs `openspec list --json` once and holds the fractions against it, which is
where 0.60 s is affordable and where the claim is worth checking.

**Merging the two records into one set of five columns.** They share `ready` and
`in-progress` and nothing else. A column called Open that means "written down,
not agreed" for an item and "the proposal is not finished" for a change is a
heading that has to be read twice, and it is what put a change into `waiting` —
a folder OpenSpec has no notion of.

**A common `BoardState` protocol** over the two vocabularies, instead of
`BoardColumn`'s two cases. Everything the board wants from a column is a title, a
summary, a colour and *whether a file can be dropped into it* — and that last one
is `nil` for every OpenSpec column. An enum says that in the type; a protocol
would have said it in a guard, in each of the two places that drop.

**`openspec list`'s `status` field as the state**, which is the obvious thing to
reach for and is wrong in two ways at once: it merges Ready with In progress, and
`complete` there means every task ticked rather than archived. It is also a
subprocess. It is used exactly once, in the test above, as a second opinion on
the fraction.

**Leaving the archive out and giving it a section under the board**, which is
what it had. That is what the report was about.

## Open Questions

- Should **Writing** offer a command too — `/opsx:continue`, or whatever the
  next artifact wants — rather than nothing? It is the same idea one step
  earlier, and the states now say which artifact is next, so the information is
  there. Left out because the apply command is the one that was asked for and a
  menu grows badly.
- Does **Writing** want splitting by which artifact is next — proposal, specs,
  design, tasks — or is one column with the answer on the card enough? One column
  is proposed; four would be a board about documents rather than about work.
- Should **Complete** and **Archived** be one column with a mark? They are
  different — one is waiting for `openspec archive` to be run — but a board with
  two columns that both mean "done" may read as a distinction without a
  difference until somebody has lived with it.
- The archive is ordered by name, which is `<date>-<name>`, so it is oldest
  first. Newest first is probably wanted, and that is a one-line decision
  somebody should make while looking at it.
