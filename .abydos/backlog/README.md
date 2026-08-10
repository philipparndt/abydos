# Backlog

One item per file — or per folder, when it carries a screenshot — in the folder
that says where it stands. Moving something along is moving its file:
`open` → `ready` → `in-progress` → `completed`.

Committed, unlike the rest of `.abydos`, for the same reason `run/` is: what is
left to do belongs to whoever is working on the project rather than to one
machine.

This file is the map. [AGENTS.md](AGENTS.md) is the workflow — what an item is
shaped like, how the spec is kept true, and the order to pick one up in. It is
one page, it is written for an assistant as much as for a person, and
`abydos-backlog init` rewrites it, so anything hand-written belongs here rather
than there.

## An item, and what it can carry

Most are one file, and stay one file: `grep` finds them and `git log` follows
them. An item that has something to show is a folder instead —

    open/0443-the-capsule-is-clipped/
      task.md      the item itself, the same markdown either way
      images/      the screenshot, the recording, the log somebody saved
      spec/        what this change does to the global spec

— and nothing had to be converted for that to be true: an entry is an item if it
is a `.md` file *or* a directory with `task.md` in it. `abydos-backlog attach
<number> <file>` turns the first into the second, so nobody has to know that.

Each carries a `## Steps` checklist, and that is the part that is not written
once: it says what is done `[x]` and what is still missing `[ ]`, ticked in the
commit that finishes each line rather than reconstructed at the end. It is what
the fraction on a card in the board is, and what `abydos-backlog show` prints
back.

## open, in-progress

Written by hand, and each one carries what has already been *ruled out* as well
as what the task is. A task that has been looked at and not solved is worth
more than a title — several of these have most of a day of searching in them,
and the point is that the next person does not repeat it.

The order within the list is what they are worth doing in: what stops somebody
working first, then what is missing, then what is only untidy. Putting an item
where it belongs is a judgement, so it stays a hand movement.

## ready

Written, understood, and *agreed* — the deciding is done, and anybody can start
without asking anybody. This is the only folder an agent picks from.

It exists because of what `open` is. Half of that list is a sentence somebody
wrote down so as not to forget it, and an agent that picks from the pile will
pick one of those and spend an afternoon inventing the parts nobody decided.
`ready` is the promise that there is nothing left to invent, which is a promise
only a person can make — so nothing moves anything into this folder
automatically, and `abydos-backlog` will not either.

An item here is picked up with `abydos-backlog start <number>`, which makes a
worktree of its own on `backlog/<number>-<slug>`, moves the item to
`in-progress` on both sides, and starts the assistant in it. A checkout each
because two agents in one working tree is two agents editing each other's
half-finished files, and what comes out is not a merge conflict but one commit
containing both.

## waiting

Written, understood as far as it can be, and stuck on something that is not
work. A crash that needs to happen again before there is anything to read; an
answer that has to come from somebody else. Kept apart from `open` so that list
stays a list of things somebody could pick up — an item nobody can act on sitting
among items anybody can is how a backlog stops being read.

An entry here says what it is waiting *for*, so it is obvious when the wait is
over. When it is, it moves back to `open` with what arrived, keeping its number.

## completed

Where an item goes when it is done, keeping the number it had. Moved, not
rewritten: what it says is what somebody knew while working on it, and the
commits it turned into say the rest.

`abydos-backlog done <number>` is the move, and it does one thing first: it
folds the item's spec delta into `spec/`. Which is the point of doing it this
way round — the spec and the code change in the same commit, and a requirement
never arrives in `spec/` before the thing it describes.

## spec

What the project *does*, one file per capability, as requirements. The other
account of the program, and the reason it is kept:

A backlog forgets. A finished item is a paragraph about a day in March, and
once thirty-three of them are in `completed/` the only remaining description of
what this program does is the program. `spec/` is the description somebody can
read in an afternoon — and the one to hand an assistant before it starts, which
is what it is really for.

It is not edited by hand while an item is in flight. A change to behaviour is
written as a delta inside the item that makes it — `spec/<capability>.md` in the
item's folder, each requirement headed `ADDED`, `MODIFIED` or `REMOVED` — and
folded in when the item finishes. Three verbs and not four: a rename is a
`REMOVED` and an `ADDED`, because a rule that only moves the heading keeps the
old sentence under the new name, which is the exact drift the spec exists to
prevent.

`abydos-backlog spec check` says whether every delta still fits the spec, which
is a thing worth knowing before a merge rather than after one.

It starts empty. Nothing was backfilled from the 33 completed items or the 390
in `history`, and that is deliberate: a spec written by reading old task
descriptions is a description of what somebody once intended, which is the one
thing it must not be. It fills up as items are finished.

## history

One file per commit, oldest first, 0001 to 0396 — the project up to the point
this backlog was written down, seeded once from:

    git log --reverse --date=short --format='%H %ad %s%n%b'

**Not a list of finished tasks, and not regenerated.** It is the commit log in
the backlog's shape, so an entry there is a change that was made rather than a
task that was closed. That is the trap this folder's name exists to avoid, and
renaming it was only half of getting out of it: six entries were commits that
did nothing but write in this folder — filing a bug, renumbering the list — and
they read exactly like the bugs they filed being fixed. They are gone from
here, which is why the numbering has holes in it. `git log` still has them, and
that is the right place for a note about the notes.

Nothing is added here again. It stops at the commit the backlog was written
down in; what is finished after that moves into `completed` as a file with the
number it was given.

## numbers

One sequence across the whole backlog, carrying on from where `history` ends:
0397 is what comes after the 396 commits behind it. A number is given once,
when the item is written, and never changes again — finishing an item moves its
file and takes its number with it.

They were not always durable. Before this, `completed` was regenerated from the
git log and the open list was renumbered from its new end, so landing anything
shifted every number after it. Files that lived through that say at the bottom
what they were called before, which is why a commit message citing an older
number still leads somewhere.
