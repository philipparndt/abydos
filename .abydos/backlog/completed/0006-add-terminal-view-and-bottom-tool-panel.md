# Add terminal view and bottom tool panel

`f11cd4f39` · 2026-07-30

TerminalView renders the emulator's grid using the same virtualisation as the
code view: only rows in the viewport are drawn, and cells are batched into runs
of identical attributes, so a full-colour screen costs a handful of draw calls
rather than one per character. Verified against a real login shell — a
powerlevel10k prompt with truecolor segments, git's coloured output and column
layout all render correctly.

Input is translated to the bytes a terminal actually sends: arrows honour
application cursor key mode, Backspace sends DEL rather than BS, Control maps to
C0 codes, and Option is Meta so word-wise line editing works. Paste uses
bracketed paste when the program asked for it, so pasted text is not executed
line by line.

The palette maps ANSI 0-15 to the editor theme so a prompt sits in the same
colour world as the syntax highlighting, while the 240 extended slots follow the
xterm cube exactly, which programs assume.

BottomPanel owns the sessions rather than the views that show them — the
groundwork for hiding an agent session and coming back to it, or taking it over
manually, while its process keeps running. ⌘J toggles, ⇧⌘T opens another.

Fixes a panel visibility bug: the initial isHidden was set in a deferred block,
so anything opening the panel during launch was silently undone when that block
ran.
