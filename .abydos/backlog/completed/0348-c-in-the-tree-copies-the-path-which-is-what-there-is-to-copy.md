# ⌘C in the tree copies the path, which is what there is to copy there

`f33d2bbfa` · 2026-08-07

The menu had "Copy Path" and the keyboard had nothing, so the one gesture
everybody tries first did nothing at all.

Answered as `copy:` rather than bound to a key. That is the same command the
Edit menu sends down the responder chain, so it arrives the way copying
arrives everywhere else: it works when the tree has the keyboard and not when
the editor does, and the menu item greys itself out when there is no row
selected. Binding ⌘C in the tree's own key handling would have been a second
way of copying that only looked like the first.

The absolute path, which is what "copy path" has meant here and what a
terminal or another program can be given. The menu still offers the relative
one, which is what a commit message or an import wants.

Checked through `NSApp.sendAction`, not by calling the method: what could be
wrong is whether the tree is ever asked, and calling it directly answers the
wrong question. The harness puts the pasteboard back afterwards — a test has
no business throwing away what somebody had copied.
