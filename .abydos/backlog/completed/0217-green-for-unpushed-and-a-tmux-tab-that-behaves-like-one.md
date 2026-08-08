# Green for unpushed, and a tmux tab that behaves like one

`f172e8efd` · 2026-08-03

The commit button says both things now: blue while there is work not
committed, green while there is work committed but not sent, and blue wins —
committing comes first, so it is what the button should be asking for while
there is any of it to do. The count comes from the same read the push button
uses, on the same occasion the tree reads the working copy.

Two things about the mirrored tabs.

Dropping a dragged one did nothing. A drop arrives through the pasteboard
path rather than the move callback, and that path looked up a session — which
a tmux window does not have, so it returned and the tab sprang back. It moves
the window now, converting the insertion index to a position, since one
counts the gaps and the other counts the tabs.

And the ✕ is gone from a mirrored tab. Killing a tmux window can take real
work with it — a build, an ssh session, an editor with unsaved buffers — and
that should not be one stray click away. The right-click menu still offers
it, where the gesture is deliberate; the name gets the room the cross was
taking.
