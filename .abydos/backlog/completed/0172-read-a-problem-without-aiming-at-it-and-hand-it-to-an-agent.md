# Read a problem without aiming at it, and hand it to an agent

`7f07fd1d3` · 2026-08-02

The message a language server reports is now written after the line it is
about, dimmed and in the severity's colour. A squiggle says where a problem
is and not what it is, and reading it meant putting the pointer on a few
characters and waiting. Settings turns it off for anybody who prefers the
quiet.

"Fix with AI" is in the editor's menu when the caret is on a problem: the
same Claude Code that reviews a branch, given the file, the line and the
message, and told to change as little as possible. It opens in the panel, so
the fix can be read and argued with.

Dragging a terminal tab onto the pane also decides its own drop now. A
terminal fills the pane it sits in, and offering the drop to a view under it
means relying on a hit test through whatever the program is drawing; where
the pointer was let go is not in doubt. The pane splits, the strip reorders,
outside the window makes a window.
