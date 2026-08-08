# A menu on an editor tab

`a5f7cbb06` · 2026-08-02

Close, Close Others, Close to the Left, Close to the Right, Close All — and
the two things anybody wants from a tab that names a file: copy its path, or
show it in the Finder. The items that would do nothing are greyed rather than
missing, so the menu reads the same wherever it is opened.

The closes walk right to left. Closing a tab shifts everything after it, and
a loop that walked forwards would skip every other one — which is the kind of
thing that looks like it works on three tabs.

Checked with four tabs open: to the right of the second leaves two, to the
left of the third leaves two, others leaves one, all leaves none. The capture
harness takes `--file` more than once now, which is what made checking that
possible.
