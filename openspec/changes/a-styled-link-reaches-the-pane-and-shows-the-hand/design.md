## Context

Three programs stand between Claude Code's `#211` and the pane, and each has
its own rule for whether a styled link survives it.

**Claude Code** writes OSC 8 when it believes the terminal will show it. The
rule, read out of the installed 2.1.268 binary on 2026-09-11: an override in its
own settings; else `FORCE_HYPERLINK` in the environment, answered by the
`supports-hyperlinks` library (`0` is no, anything else yes); else
`TERM_PROGRAM` one of `ghostty`, `Hyper`, `kitty`, `alacritty`, `iTerm.app`,
`iTerm2`; else JetBrains's `TERMINAL_EMULATOR`; else Windows Terminal outside
tmux; else `TERM_PROGRAM=tmux` with `TERM_PROGRAM_VERSION` 3.4 or newer; else
`LC_TERMINAL` on that list; else a `TERM` containing `kitty`; else no.

**tmux** keeps every hyperlink a pane writes and forwards it to a client only
when that client's terminal has the `Hls` capability, which the `hyperlinks`
terminal feature supplies. The feature is not inferred from `xterm-256color`'s
terminfo, and the user's `terminal-features` on this machine adds `extkeys` and
`RGB` and not this. Measured through a pty against tmux 3.7c with `-f
/dev/null`:

| tmux client started with | OSC 8 sequences reaching the client |
| --- | --- |
| nothing | 0 of 2 |
| `-T RGB` | 0 of 2 |
| `-T RGB,hyperlinks` | 2 of 2, as `ESC ] 8 ; id=tmux1 ; url ESC \` |

**This terminal** reads OSC 8 in both engines. `TerminalEmulator.applyHyperlink`
splits the body at its first `;`, so tmux's `id=tmux1` parameter is dropped and
the address kept; libghostty-vt hands back the URI per cell. `link(atWindowPoint:)`
finds a marked run by the id its cells carry and a printed address by scanning
the row's text, and `updateHoveredLink` asks it only while ⌘ is held.

## Goals / Non-Goals

**Goals:**

- A styled link a program writes inside the tmux this app starts reaches the
  pane as a link.
- A program in a bare pane that asks the convention's question is told this
  terminal shows hyperlinks.
- A marked link says it is one under the pointer without ⌘; a printed address
  keeps waiting for ⌘.
- The click rule is unchanged: ⌘ opens, a bare click selects, a tracking
  program is not stolen from.

**Non-Goals:**

- Telling Claude Code the pane *is* Ghostty. `TERM_PROGRAM=Abydos` is set on
  purpose so `abydos <file>` can tell this window from Ghostty, and lying to
  one program to please another is how the afternoon in
  `PseudoTerminalEnvironment`'s comments was lost.
- Opening a marked link on a bare click. That was the behaviour until
  2026-09-10 and it was removed for springing on exactly the text somebody
  wanted to copy.
- Reaching into somebody's `.tmux.conf`. The feature is declared by the
  client this app starts, for that client, the way `RGB` already is.

## Decisions

**`-T RGB,hyperlinks` on the client, not `terminal-features` on the server.**
`-T` names what *this* client's terminal can do and touches no session or
config anybody else has. `set -as terminal-features ',*:hyperlinks'` would say
it for every client of the server, including one attached from a terminal that
cannot show them. tmux takes `-T` from 3.2, the floor `RGB` already set.

*Ruled out: leaving it to the user's `.tmux.conf`.* The report is from the
maintainer, who has one, and it does not say so; nobody else's will either.

**`FORCE_HYPERLINK=1` in the pane's environment, defaulted rather than set.**
`??`, like `TERM` and `COLORTERM`: a value somebody exported to say no is
theirs. Under tmux the variable is beside the point — `TERM_PROGRAM=tmux` on
3.4 or newer already answers yes — so it does its work in a bare pane and is
harmless in the other.

*Ruled out: `LC_TERMINAL=iTerm2` or a `TERM` containing `kitty`.* Both are the
lie the non-goal names. *Ruled out: doing nothing for a bare pane.* Nearly every
pane here is a tmux client, but a pane that is not would show plain text where
the tmux one shows a link, and the difference would read as a bug.

**A marked link shows itself on plain hover; a printed address still needs ⌘.**
The program said "this is a link"; the underline and the hand are the
terminal agreeing, and every browser does the same. A printed address is the
terminal's guess from a regular expression, and a guess drawn over somebody's
text as they move the mouse across it is noise — so that keeps ⌘, as
Terminal.app and iTerm2 keep it for both kinds.

Cost: `mouseMoved` now asks for the link on every move, not only with ⌘ held.
The marked half of the lookup is one cell's attribute and a walk along its
run; the printed half is the row scan, and that is done only with ⌘, in
`link(atWindowPoint:)` itself, so the order of the two checks is what keeps a
plain move cheap. Nothing here runs per frame.

*Reversed the same day: a plain click opens a marked link after all.* The
first cut kept the click on ⌘ — the underline changes what the pointer says,
not what the click does — and the maintainer, hovering one: *"this is
unintuitive as it already underlines/hovers"*. A hand is a promise about the
click, and a hand that needs ⌘ breaks it. What the bare click was removed for
on 2026-09-10 is a different gesture: a press that *travels*, on the text
somebody wanted to copy. So the press on a marked link is held, and the
release decides. Released within the click slack — the same cell-sized slack
that already keeps a wobbling click from becoming a drag report to tmux — it
is a click and opens; travelled a cell, it becomes the selection or the
forwarded press it would have been, begun late by a cell nobody can see. A
program tracking the mouse hears nothing of a click that opened, as it hears
nothing of a ⌘-click. Shift still forces a selection. A printed address keeps
the old rule entirely, since nothing about it is shown until ⌘ is held.

*Ruled out: opening on the press.* That is the 2026-09-10 fault exactly: a
drag begun on a link opens it before it can select. *Ruled out: a double-click
guard.* The first click of a double-click on a link opens it, as it does in a
browser; the second selects a word, which is harmless beside the page that is
already opening.

**The address as a tooltip over a marked link.** `#211` is a promise with no
destination in it; a browser shows where a link goes in its status bar before
the click, and the maintainer asked for the same (*"maybe we should show the
link as hover"*, 2026-09-11). A tooltip rect over the link's cells, made when
the hover begins and removed when it ends, owned by the view and reading the
address off `hoveredLink` — AppKit does not retain a string handed to it as
the owner, which `DebugToolbar` learnt the hard way. A printed address is its
own text and gets none.

*Ruled out: the view's `toolTip` property.* It is one tip for the whole view,
shown wherever the pointer rests, and would say the last link's address over
plain text a moment after leaving it.

**`--terminal-link <row>:<column>:hover`** reports the hover with no modifier,
beside the existing ⌘ hover, `click` and `bare`. The claim is two lines from
one run: a marked link underlined without ⌘, a printed address not.

## What was measured, 2026-09-11

A throwaway build driven on a scratch project, the pane a client of this
machine's own tmux under the session the folder names, `#211` marked with
OSC 8 and `https://example.org/x` printed after it on row 0, the GPU renderer
drawing:

| `--terminal-link` | Result |
| --- | --- |
| `0:1:hover` — the marked link, nothing held | `modifier=none columns=0…3 url=https://github.com/o/r/pull/211 marked=true underlined=true` |
| `0:12:hover` — the printed address, nothing held | `modifier=none none underlined=false` |
| `0:12` — the printed address, ⌘ held | `modifier=cmd columns=9…29 url=https://example.org/x marked=false underlined=true` |
| `0:1:bare` — a plain click on the marked link, first cut | `opened=0`, and the click went to the program, which was tracking the mouse |
| `0:1:bare` — a plain click on the marked link, the reversal | `opened=1 selected=""`, and the program tracking the mouse heard nothing |
| `0:1:drag` — a press on the marked link that travels two cells | `opened=0`; the press and the drag went to the program, which was tracking the mouse |
| `0:12:bare` — a plain click on the printed address | `opened=0`; the click went to the program |
| `0:1:click` — ⌘-click on the marked link, after the reversal | `opened=1`, as before |
| `0:1:hover` — the marked link, once the tooltip was added | `tip="https://github.com/o/r/pull/211"` |
| `0:12` — the printed address under ⌘, the same build | `tip=none` |

The first row is also the tmux half of the proof: the link was written by
`printf` inside the pane's tmux, and `marked=true` at the pane means the client
started with `-T RGB,hyperlinks` was handed it. Before this change the same
bytes reached the pane as plain text, which is the report.

## Release note

> **A link a program styles is a link here too.** Claude Code's `#211` for a
> pull request, and anything else a program marks with OSC 8, arrives in the
> pane as a link through tmux — the client this app starts now tells tmux the
> terminal shows hyperlinks, which is what tmux waits to hear before it
> forwards one — and a program in a pane without tmux is told the same in the
> word the `supports-hyperlinks` convention reads. A styled link is underlined
> and the pointer is a hand as soon as the pointer rests on it, no ⌘ needed;
> a plain click opens it, a tooltip says where it goes, and a drag that
> starts on it still selects. A plain
> web address a program printed still shows itself under ⌘, and ⌘-click opens
> either.

## Risks / Trade-offs

- [Another tool that honours `FORCE_HYPERLINK` starts writing OSC 8 in a bare
  pane — `ls`, `rg --hyperlink-format`, `bat`] → that is the point: the pane
  shows them. A tool that writes them badly shows its own bug, as it would in
  kitty.
- [A very long row with a marked link is walked on every mouse move] → the
  walk stops at the run's edge and reads one attribute per cell; a row is at
  most a few hundred cells.
- [tmux older than 3.2 refuses `-T`] → already the floor since `RGB`; nothing
  new is asked of it.

## Open Questions

None. Whether Claude Code's own settings override (`hyperlinks` in what the
binary calls `Tl()`) is documented is not known and is not needed: the tmux
path is decided by `TERM_PROGRAM=tmux`, and the bare path by `FORCE_HYPERLINK`.
