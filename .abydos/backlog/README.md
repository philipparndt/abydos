# Backlog

One file per item, in the folder that says where it stands. Moving something
along is moving its file: `open` → `in-progress` → `completed`.

Committed, unlike the rest of `.abydos`, for the same reason `run/` is: what is
left to do belongs to whoever is working on the project rather than to one
machine.

## open, in-progress

Written by hand, and each one carries what has already been *ruled out* as well
as what the task is. A task that has been looked at and not solved is worth
more than a title — several of these have most of a day of searching in them,
and the point is that the next person does not repeat it.

The order within the list is what they are worth doing in: what stops somebody
working first, then what is missing, then what is only untidy. Putting an item
where it belongs is a judgement, so it stays a hand movement.

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
