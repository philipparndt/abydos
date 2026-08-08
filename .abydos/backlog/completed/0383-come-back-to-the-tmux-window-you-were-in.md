# Come back to the tmux window you were in

`afa276e23` · 2026-08-08

Reopening a project put the terminal on whatever window tmux happened to
have selected, which after a restart is rarely the one somebody left.
Hunting through a tab strip for work you put down ten seconds ago is a
poor way to be welcomed back.

The window is remembered beside the project with everything else that is
— what was open, where the panel was, which breakpoints — and selected
again when the project opens, before the terminals come back, so the tab
strip appears already showing it rather than showing one and then moving.

By tmux's own id rather than by index, for the reason in 45f26a0: an
index is where a window sits and windows do not stay there.

Quietly when the window has gone. The server may have been restarted or
the window closed, and neither is something anybody did wrong: tmux's own
choice stands, which is exactly what happened before this was written.

A session that remembers only a window is still worth writing, so this
works for a project with nothing else open. One saved before any of this
existed reads as having none rather than failing to read.
