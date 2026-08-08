# Push a branch, open it on GitHub, and keep stashes where the branches are

`c7f1d5533` · 2026-08-03

Three things a repository needs that were a trip to a terminal.

Pushing, from the branch itself: "Push 32 Commits" on a branch that is ahead,
"Publish Branch" on one that has never been pushed — which is the case the
list could not even tell apart before, since a branch level with its upstream
and a branch with no upstream both count nothing. It knows its upstream now.
Any branch, not only the one checked out: checking a branch out to push it is
a detour through the working copy for something that never touches it.

Opening it where it lives: read from the remote, so github.com and an
Enterprise install are the same case and the menu says which one it is going
to. Every shape git accepts is handled, including the scp-like one that is
not a URL at all, and a remote with no website — a path — offers nothing
rather than inventing an address.

And stashes, in the branches view rather than a view of their own, which is
what the branch list is for: work that is not on a branch, kept beside the
branches it came off. Apply asks whether the entry should stay or go, because
that depends on whether the work is being resumed or borrowed and nothing
here can know which. Drop takes as many as are selected — highest first,
since git renumbers what is left after each one. Rename works by dropping the
entry and storing the same commit under the new message, in that order: a
reflog records changes of value, so storing a commit the stash already points
at writes nothing and the rename silently does nothing. That was found by
running it.

Stashing from the commit view too: everything, or the files chosen — with the
untracked ones, since the point is a clean working copy and one with new
files still in it is not clean.

Seven tests drive real repositories, because every claim here is a claim
about what git does. And while looking at it: text in the sidebar rows now
stops inside the selection rather than running out past the pill.
