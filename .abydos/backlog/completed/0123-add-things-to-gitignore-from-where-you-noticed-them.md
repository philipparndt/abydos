# Add things to .gitignore from where you noticed them

`d11812df7` · 2026-08-01

Right-click an untracked file — in the changes list or in the tree — and
ignore it. The pattern is offered rather than imposed: "ignore this" can
mean this exact file, anything with this name, everything with this
extension, or everything this build step produces, and guessing wrong writes
a line into a tracked file somebody else has to notice and undo.

So the suggestions are a list with a plain-English explanation each, and the
field stays editable. The exact file comes first, being the only one that
cannot cover more than was meant. A name ending in digits — `__debug_bin`
followed by a number that differs every run — also offers the prefix, since
ignoring only today's build is useless tomorrow.

Offered only for untracked files: ignoring one git already tracks does
nothing, and a menu item that does nothing is worse than no menu item.
