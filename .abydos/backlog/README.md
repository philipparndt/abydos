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

Numbered on from where `completed` ends — one sequence across the whole
backlog, so 0385 is simply what comes after the 384 commits behind it. Within
that, the order is what they are worth doing in: what stops somebody working
first, then what is missing, then what is only untidy.

The numbers are the list's, not an identity. Two things follow, and both are
fine as long as they are known:

- They shift. Landing a task turns it into commits, which take the next numbers
  in `completed`, and the open list is renumbered from the new end. Rebuild
  both together or they will collide — `completed` numbers by commit ordinal
  and does not know the open list exists.
- A commit message citing a number is citing the number of that moment. Each
  file says at the bottom what it has been called before, which is the only
  reason those references still lead anywhere.

The durable identifiers are the commit hashes. Everything else here is a
position in a queue.

## completed

Generated from the git history, one file per commit, oldest first. Every commit
message in this project says what changed and why, so the history already is
the record of what was done; this only puts it where the rest of the backlog
is. It can be rebuilt at any time and nothing is lost by deleting it:

    git log --reverse --date=short --format='%H %ad %s%n%b'

Which is also why nothing is written here by hand. A file that could not be
regenerated would quietly become the only copy of something.
