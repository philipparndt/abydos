# Support git worktrees

`988008023` · 2026-08-01

A worktree is the answer to "I need to look at another branch without
putting this one down": a second directory on the same repository, with its
own index and its own checked-out files. The alternative is stashing, which
is a worse version of the same thing.

They are listed under the branches, since that is where somebody looks for
"where else is this repository checked out". Opening one switches the window
to it — it is already a checkout, so there is nothing to check out — and the
window keeps what each project had open, which the terminal-following work
already provides. New Worktree makes one beside the repository rather than
inside it: a worktree within the work tree shows up as an untracked
directory in its own status, and the first thing anybody would do is add it
to .gitignore, which is a worse answer than putting it somewhere else.

Removing asks first and then forces, because the useful case is exactly the
one plain remove refuses: a worktree with something uncommitted in it that
you have decided to abandon. The branch is left alone either way. One whose
directory somebody deleted by hand is shown as missing rather than silently
listed as though it were there.
