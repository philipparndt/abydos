# 443. A backlog somebody can hand to an agent: ready, a spec, and a board

This folder was already the best thing in the repository and the least usable
by anything but a person. Four hundred and thirty-five files, each of them
worth reading, and no way to say "here, do this one" — an agent pointed at
`open/` picks a sentence somebody wrote down at a traffic light and spends an
afternoon inventing the parts nobody decided.

Three things were missing, and they are one thing: **`ready`**, so there is a
folder that means the deciding is done; **`spec/`**, so what the program does
survives the items that made it do it; and a **board**, so moving something
along is a gesture rather than a `git mv` somebody has to remember the folder
names for. Plus the command line all three are worked from, since the agent is
in a worktree over a terminal and there is no window there to click in.

Openspec is where the shape came from — a global spec, per-change deltas with
`ADDED`/`MODIFIED`/`REMOVED`, an `AGENTS.md` every tool is pointed at. What is
not borrowed is the storage: this stays files in folders, because that is what
made this backlog worth keeping and a database would be the end of it.

## Ruled out

**A field in the file saying which state it is in.** The state is the folder
and nothing else. Anything else can disagree with where the file actually is,
and then there are two answers and no way to tell which is stale. The cost is
that a state change is a rename in `git log` rather than a one-line diff, which
turns out to be the better half of the trade: a rename is a thing you can see
in a diff and revert with another one.

**Making every item a folder.** Four hundred and thirty-five of them exist as
files, and 400 will never carry a picture. So an entry is an item if it is a
`.md` file *or* a directory with `task.md` in it, both shapes read the same way
everywhere above `BacklogItem`, and `attach` converts on demand. Nothing had to
be migrated for screenshots to work, which is the whole point.

**Backfilling the spec from `completed/` and `history/`.** Tempting — 423
entries, and the spec starts empty. But a spec written by reading old task
descriptions is a description of what somebody once intended, which is the one
thing it must not be. It fills up as items are finished.

**Four verbs in the delta.** `RENAMED` was drafted and dropped: a rule that
moves a heading and keeps the body silently keeps the old sentence under the
new name, which is the exact drift the spec exists to prevent. A rename is a
`REMOVED` and an `ADDED`, and writing both is the point.

**Refusing to finish an item whose delta will not fold.** `done` prints every
problem and completes anyway. The alternative leaves the item in
`in-progress/` with the work merged, which is a worse lie than a spec with a
gap in it that was just printed on the terminal.

**Picking ready items up automatically.** Nothing sweeps `ready/` and starts
agents. The button and the menu item start one, a person presses them. An
editor that quietly spawns processes against a cluster because a file moved is
not a thing to build by accident.

**One shared `.claude/` ignore.** This repository ignored the whole directory,
for the worktrees agents leave in it. That also ignored the skill files `init`
writes, so they would have worked perfectly for whoever ran it and not existed
for anybody who cloned. Narrowed to `.claude/worktrees/`, and `init` now runs
`git check-ignore` over what it wrote and says so — the failure is otherwise
silent and only shows up as an assistant that has never heard of the backlog.

## Steps

- [x] `BacklogState`, and `ready` between `open` and `in-progress`
- [x] An item is a file *or* a folder with `task.md`, read the same way
- [x] `attach` converts on demand, and keeps a second `Screenshot.png`
- [x] The global spec, deltas, and a fold that says what would not go
- [x] `abydos-backlog`: init, new, list, show, move, attach, next, start,
      spec, fold, done, runs
- [x] `init` asks which assistant, and writes its skill file — Claude Code,
      Copilot, opencode, Codex, Cursor
- [x] A shared file keeps what its author wrote; ours is one fenced section
- [x] `start` makes a worktree on `backlog/<n>-<slug>` and moves the item on
      both sides
- [x] The dashboard: a list and a board, dragging between columns
- [x] `## Steps` — what is done `[x]` and what is missing `[ ]`, on the card
      as a fraction and a bar
- [x] Tests: 43 across the model, the spec, `init` and the runner
- [x] This project's own backlog brought up to date, and `project.md` written
- [x] `spec/backlog.md` says what the project now does
- [ ] Somebody other than the author runs `init` on a project that is not this
      one

      **Closed with this one unticked, on 2026-08-16, at Philipp's word.** Half
      of it was done and the half that was not is the half that matters. What
      was checked: `init --assistant claude --yes` in a throwaway git
      repository holding one Python file, from outside this project — twelve
      files written, `new` numbering from `0001`, `status` reading the new
      backlog, and a second `init` answering "12 already there and left alone",
      which is this delta's own *running init twice* scenario exercised
      somewhere that is not the repository it was written in.

      What was **not** checked, and cannot be by anybody who has read this
      code: whether a person who has never seen the backlog can follow
      `AGENTS.md` and get anywhere. That is the whole point of the step and it
      needs somebody else. It is a question about the writing rather than about
      the program, so it does not hold the item open — but it has not been
      answered, and a later item that finds `init` confusing should know that
      nobody ever sat and watched a stranger use it.

## Not doing here

**A `waiting` reason as a field.** It stays prose in the item, as it always
was. The README already asks for it and the honest answer is that nobody reads
a field.

**Sorting within a column.** Number order, and a drag moves between columns
only. Two people dragging cards up and down one list disagree, and neither of
them knows.
