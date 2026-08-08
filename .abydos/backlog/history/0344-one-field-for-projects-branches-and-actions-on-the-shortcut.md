# One field for projects, branches and actions, on the shortcut hands already know

`d3a124d43` · 2026-08-07

⇧⌘P, because a decade of VS Code has taught everybody's hands where a palette
lives, and muscle memory is worth more than a free letter. Presentation Mode
had it and moved to ⌃⌘P: once a quarter against several times an hour.

Typing now searches three things. Branches come from the open repository and a
chosen one is checked out exactly where the branch menu would have put it —
the checkout is shared rather than written twice. Actions are the handoffs the
branch menu offers, flattened: a submenu cannot be typed at, so the host's
pages became rows of their own and are found by the words in them.

The project list is capped at eight with the count in its header. A two-letter
query matches ninety-two of them, and without a limit the branches and actions
underneath sit below a hundred rows, which is the same as not being there.

Asking git for the current branch rather than GitRepository.currentBranch(),
which answers from a cache only a loaded repository fills — a fresh one says
nil however checked out it is, and Open Branch on GitHub never appeared.
