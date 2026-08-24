# Abydos 0.5.0

**Git was three tool windows, five lists and two search fields, and it still
could not make a tag.** It is one button now — ⌘2 — with one tree behind it, and
the two things you sit down to do have pages of their own: the log on ⇧⌘L, the
commit on ⇧⌘K.

The tag was the tell. `GitTags.recreate` has always taken "anything git can
resolve — a commit, a branch, a tag", so pointing `v1` at `main` worked from the
first day and nobody could do it: every verb in this app hangs off the menu of a
row, and a tag that does not exist yet has no row to right-click. The same rule
explains the rest of what was missing. Fetch and pull act on the repository, and
no pane drew the repository. Revert, cherry-pick and reset act on a commit, and
the pane that drew commits offered `Copy Commit Hash` and `Copy Subject`.

## One tree

The working copy, the stashes, local branches, each remote, tags, worktrees.
Branch names fold on `/`, so `feature/tags` and `feature/stash-preview` sit under
one row — and a prefix holding a single branch stays flat, because a folder that
exists to hold one row has turned one row into two and said nothing. Typing in
the filter flattens the whole thing: a tree you have to expand to reach a name
you have just typed is worse than no tree.

The working copy arrives shut. Every change unrolled under the first row pushes
the branches off the bottom of a column, and the question the tree is usually
asked is *where am I* rather than *what have I changed* — which is what the
commit page is for.

## Two pages

**⇧⌘L** opens the log where a graph has room for its lanes: refs as labels,
author and date as columns, and the selected commit's files and diff beside it
rather than in a tab somewhere else. Commit messages render as markdown, which is
what they are written in. **⇧⌘K** opens the commit view the same way — the two
lists, the diff beside them, and a message field with room for a description.

They are the same class at two sizes, and so are the sidebar's trees. That is not
tidiness: the loader, the collapse rule, the graph and the menus cannot drift
apart when there is only one of each.

## Nothing destroyed without being said, and nothing lost

Switching a branch over uncommitted work, discarding, resetting, rebasing,
amending, deleting a branch that is ahead and moving a tag each say what they
will cost — leading with a number, because "4 commits leave main" is read and
"this cannot be undone" is not — and leave a real branch under `backup/` before
they run. A toast afterwards names it and offers to undo.

**A branch and not the reflog**, because reflog entries for unreachable commits
expire and `gc` collects what they pointed at. Not a private ref namespace
either: safety nobody can find with `git branch` is not safety.

Work that is not committed is captured without being disturbed. `git stash
create` was the obvious way and is the wrong one — it has no `--include-untracked`,
so discarding a file git had never seen would have been "insured" by a commit not
containing it.

Force-pushing a branch is the one thing here that is **not** insured, and it says
so: no local ref can recover somebody else's commits from a remote.

## Pull, which never existed

Remote and branch pickers, the branch it goes into stated and not editable,
`Rebase instead of merge` and `Stash and reapply local changes`. Both are
remembered — and a repository with `pull.rebase` in its own config overrules the
app and says where the setting came from. A pull that fails for want of a
credential says that, rather than returning an exit code with nothing beside it.

## Stashes worth looking at

A stash opens to what is in it, including the files git had never seen — they
live in a parent of their own, so anything reading only the diff was missing
exactly the files somebody had forgotten they had. Each says whether it would
still apply, checked without touching the working copy, and where it would not,
branching from it is offered instead: applied on the commit it came from, it
cannot conflict. Selected lines can be stashed on their own.

A checkout git refuses over a dirty working copy now offers to stash, switch, and
give the work back when you come back — the second refusal this app can act on,
after the one about a branch another checkout holds.

## A conflict says so

Nothing on screen said a merge was half-done. The header now does, with three
things and deliberately not four: open the conflicted files, open in Fork, or
copy a prompt describing the conflict for a session in the terminal below.

## Messages, drafted

**Draft** on the commit page writes a summary and description from what is
staged — not the working copy — with this repository's last twenty subjects
alongside, so the draft is written the way this project writes. It fills two
fields and stops: nothing is staged, nothing is committed, and Commit is never
disabled while it thinks. That the diff is sent is said once, per project,
before the first time.

## Also

- Tags can be created, moved onto a branch or a commit, and deleted. The sheet
  that moves one resolves the target in front of you before you press the button.
- Fetch, pull, force-push-with-lease, revert, cherry-pick, reset, checkout a
  commit, branch from a commit.
- A Git section in Settings: how this project pulls, and how long backups are
  kept.
- Diffs show old and new line numbers.

## One fix worth its own heading

An abort inside CoreText has crashed this app three times, months apart, on "a
nil that no line of this app's source can be seen to have produced". The third
report named the frame. `+[NSFont systemFontOfSize:weight:]` is nullable in
Objective-C and imported into Swift as non-optional: when the font system
refuses, what comes back is a nil wearing a type that says it cannot be one, and
nothing goes wrong until CoreText copies it into an attributes dictionary and
aborts, several frames and one run loop turn from the mistake. Every font this
app builds now goes through one guard.

## What is deliberately still Fork's

Interactive rebase, three-way merge editing and blame archaeology. Abydos owns
the git you do *while* writing code; the branch pill and the conflict banner both
offer Fork for the rest, and that is now a stated contract rather than a fallback.
