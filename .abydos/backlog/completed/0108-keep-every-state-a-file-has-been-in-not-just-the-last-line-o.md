# Keep every state a file has been in, not just the last line of them

`7506175ea` · 2026-08-01

Undo was two stacks, which means typing after an undo silently destroys what
was undone. That is the one moment in editing where the machine throws work
away without saying so, and it happens constantly: undo a few lines, try
something else, and the first attempt has never existed.

The history is a tree now. Typing after an undo adds a branch beside the old
one rather than deleting it, so every state the file has been in stays
reachable. ⌘Z and ⇧⌘Z walk the trunk as before — redo without being asked
which way takes the most recent branch, since that is the one being worked
on — and ⌥⌘Z opens the list of states, including the ones on branches that
were left behind and that no amount of redo would reach.

Getting between two states is one mechanism: walk up to the nearest shared
ancestor undoing, then back down applying. Undo and redo are that with the
destination worked out for you.

Shown as a list rather than a drawn tree. A tree of edits looks impressive
and answers nothing; "what changed, when, and is it on the way to where I am
now" is the question actually being asked, so branches are marked rather
than drawn.
