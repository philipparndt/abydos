# Review uncommitted changes as well as a branch

`423545356` · 2026-07-31

Uncommitted work is the case you want reviewed most often — it is the
code you are still holding, before it is written down — and it is the
one a branch diff cannot express: `git diff base...HEAD` shows committed
history and says nothing about a working tree.

A review now carries a scope. The uncommitted prompt names staged,
unstaged and untracked work separately, because each is invisible to the
command that shows the others: `git diff` misses staged edits,
`--cached` misses unstaged ones, and neither shows a file that has never
been added. It also says not to review anything already committed, so
the two scopes do not overlap.

⇧⌘U, next to ⇧⌘R for the branch. The session is titled "Review
(uncommitted)" so the two are tellable apart in the same tab strip.

A clean working tree is reported straight away rather than by starting an
agent and waiting a minute to be told there was nothing there. That and
the existing start failures now use a window sheet instead of an
application-modal alert: it is attached to the window it concerns and
does not stop the rest of the app.
