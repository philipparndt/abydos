# Abydos 0.20.4

Seven fixes and small features, most of them from people who wrote in.

## Web addresses in the terminal open on ⌘-click

Hold ⌘ over an address in a pane — one a program printed, or one it marked as a
link — and it is underlined and the pointer is a hand; ⌘-click opens it in the
browser. A bare click selects text as it does everywhere else, which it did not
over a marked link before. The address is found in the row's own cells, so a
wide character before it does not shift the underline, and a trailing full stop
or a bracket the address did not open is left out. The underline is drawn by
both renderers now — the GPU path never drew one at all, so a link there was
only ever a cursor change.

## Shift+Return breaks the line

The usual line break is Shift+Return, and most terminals answer it; this one
answered Option only, and Shift+Return submitted the half-written message. It
now sends the same newline Option+Return does, through tmux and without it —
the sequence Claude Code's own terminal setup binds Shift+Enter to. A program
that asked for the keyboard protocol still gets its own form.

## A TUI's highlights can be read under the Level AAA theme

k9s's selected row, its crumbs, a status bar — dark text a program paints on a
bright colour — came out grey under the AAA theme and dull under the others.
Bold has brightened the first eight terminal colours since xterm, and did so on
a painted background too, turning a program's black into the palette's dim grey
on its aqua. Bold brightens on the terminal's own ground only now, and tmux is
told outright that the terminal shows true colour, so a program's own colours
arrive as it sent them.

## A completion listing scrolls instead of overwriting

Under the app's own terminal engine inside tmux, a shell's `cd`-tab-tab listing
could leave stale rows on the screen that only a repaint cleared. The alternate
screen was advancing its count of discarded history on a scroll that discarded
none — it has no history to discard — and the renderer then drew a row off from
where the grid held it. The count is left alone where there is no history, and
the two agree again.

## A paste into a tmux terminal no longer leaks `[200~`

Pasting through tmux, a rare miss in reaching tmux fell back to writing
bracketed-paste markers from the outer terminal's mode rather than the shell's,
and when they disagreed the marker landed in the command line as `[200~`. The
tmux paste is retried now, and if tmux truly cannot be reached the text is
pasted plainly — never with a marker the shell did not ask for.

## Returning to the settings page leaves the terminal alone

With the settings page open and the terminal maximised, two things used to
un-maximise it: pressing ⌘, to return to the page that was already open, and — the
one people actually hit — a window following its terminal between two projects,
which restores the project's open pages on every tmux window switch. The four
git pages already knew not to take the window when restored; the settings page
was the one that did not. Now none of them do, and returning to a maximised
terminal keeps it maximised.

## A double-click on the tab strip is yours to choose

A double-click on the empty part of the editor's tab strip expands and collapses
the editor now, as the maximise button beside it does; it used to open a scratch
file. A setting under *Editor* offers the old behaviour back — a scratch in this
project — or a global scratch, and the strip's menu still makes either in one
click.
