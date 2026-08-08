# Each + makes another of the tabs beside it, and the tmux tab is called tmux

`69578fc14` · 2026-08-05

Two strips, two meanings, and the button has now had both of them — one after
the other, each wrong the same way. It was told about tmux rather than about
the tabs under it: first the panel's own + put plain shells into a strip whose
windows were tmux's, then the fix for that made tmux windows from the strip
that holds everything except them.

What a + means is what the tabs beside it are. The top strip holds the panel's
own panes — the terminal attached to tmux among them, a debugger, a run — so
its + opens a terminal. The green strip below holds tmux's windows, so its +
makes a window. The one case where the top + still makes a window is the
single-strip layout, where tmux's windows *are* those tabs and there is no
strip below to press.

The tab for the attached terminal is called `tmux`, in every project. It was
called after the session, which is the project's name, so the one fixed tab in
the panel read as a different thing everywhere — `ideai` sitting beside a
debugger says nothing about what the tab is, and which session it holds is
already written on the tag at the end of the strip below. Four places could
name it and now agree: the tab, the terminal created when it attaches, the
title a tmux client reports (it reports session:window, which is not a name for
the tab that stands for the client), and what was written down last time. A
name somebody typed still wins.

Checked against a real session rather than only in a test, since that is where
the last two attempts passed and the button still did the wrong thing: the top
+ takes the panel from one pane to two and leaves tmux's window list alone, and
the + below takes tmux from two windows to three and adds no pane.
