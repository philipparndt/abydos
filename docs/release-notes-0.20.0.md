# Abydos 0.20.0

## The download runs on an Intel Mac

Every release so far carried an Apple silicon binary only, so on an Intel Mac
the app refused to open. The image is universal now: one download, both
processors, the same signature and notarisation. macOS 26 is the last release
for Intel Macs and Rosetta is being wound down, so this is for the machines
still in use rather than a long-term promise. Not tested on Intel hardware —
there is none here — but the Intel half opened a project and zoomed under
Rosetta.

## A double-click on the title bar zooms the window once

Double-clicking the title bar zoomed the window and it came straight back. It
had been reported for weeks, measured once and found correct, and it was two
zooms by two authors: the strip drawn where the title bar would be answered the
second press itself, and AppKit answered the second release. Since the end of
August the installed binary is marked as built against the macOS 14 SDK, under
which AppKit handles the gesture for such a strip on its own — so from that day
every double-click was a zoom and an un-zoom. The strip no longer handles the
gesture; AppKit does what your system setting says, as for every other window.
Measured from outside the process with real mouse events, before and after.

## The light theme's terminal can be read, and one theme reaches WCAG Level AAA

A user said the light terminal could not be used, and measured, they were
right: in the default palette thirteen of the sixteen colours were under 4.5:1
against the light ground, bright green at 2:1. Every shipped palette's light
half is darker now, each colour keeping its hue and clearing WCAG's floor for
text on every ground it is drawn on; in the dark theme nine values moved by a
shade, the dim grey most, so a comment in a prompt can be found. A test measures
every palette on every run and names the colour that falls short.

The themes themselves are measured the same way now — the editor's text, the
sidebar's, the git colours, every syntax kind against the ground it sits on —
and twenty values moved by a shade to clear 4.5:1, most in the light halves.
Line numbers, ignored files and comments are meant to recede and are held to
3:1.

New in the Theme list: **WCAG Level AAA**, the blue theme's hues at 7:1
throughout, for anyone who finds 4.5:1 tiring, with a terminal palette of the
same name as its terminal. The palette is also on its own under Terminal
colours, for use beneath another theme. A theme of your own can promise its
floor with `"floor": 7` in its file and the test holds it to that.

One trade is visible: a powerline prompt paints these colours as backgrounds
and puts dark text on them, and a colour that reads as text on white cannot
carry near-black text at 4.5:1. Light terminal prompts want light text on their
segments, as they do everywhere.

## Settings can be filtered

A field at the top of the settings sidebar narrows the list to the sections
with a match and shows the matching rows of all of them together, each under
its section's name. It matches the help under a control as well as its title,
so "ghostty" finds the terminal engine and "tmux status" finds the status-bar
switch. ⌘F puts the cursor in it.

## The project view keeps its place across a rebuild

Every rebuild of the tree — a session event, a file changing under a watched
folder, a settings change, the reload when the window comes forward — now puts
the scroll back on the row that was at the top, at the same offset, beside the
expansion and selection it already kept. Reported as the tree scrolling up while
a session's screenshots were being read. The rebuilds a driven run can trigger
did not move the tree before this change either, so if it still jumps, say which
rows were on screen.

## A file opened from inside an archive is found in the tree

*Find File in Editor* on an entry opened from a zip said the file was not in the
tree and named a cache path as the reason. The row was there the whole time, two
rows inside the archive it came from, and is found now.

## Behind the release

The tap can no longer be pointed at a release that is not there: it asks GitHub
for the tag and compares the served image's digest with the checksum the cask
pins before anything is written. `abydos-diff`, used as a git difftool, opens
the installed app — or the checkout's own build when asked from one of that
checkout's panes — rather than whichever registered copy Launch Services chose,
which was a build nobody was looking at about half the time. And a completion
listing that overwrites the
rows above it under tmux with its status bar hidden is reproduced and narrowed
to one path in the emulator; the fix is still open and the pane redraws
correctly at the next repaint.

Most of the commits since 0.19.1 split long source files at what each part
does. They changed nothing about the program and are not here.
