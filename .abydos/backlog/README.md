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

## completed

Generated from the git history, one file per commit, oldest first. Every commit
message in this project says what changed and why, so the history already is
the record of what was done; this only puts it where the rest of the backlog
is. It can be rebuilt at any time and nothing is lost by deleting it:

    git log --reverse --date=short --format='%H %ad %s%n%b'

Which is also why nothing is written here by hand. A file that could not be
regenerated would quietly become the only copy of something.
