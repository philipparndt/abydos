## Context

The terminal knows one kind of link: the kind a program marks. OSC 8 gives a run
of cells a link id (`TerminalAttributes.link`), both engines answer
`link(for:)` with the address behind an id, `updateHoveredLink` in
`TerminalView+Mouse.swift` turns the pointer into a hand over such a cell, a bare
click in `mouseDown` opens the address before selection is considered, and the
GPU renderer underlines the hovered id (`TerminalMetalRenderer.swift:631`) —
the CoreGraphics renderer does not, having no `hoveredLink` in its drawing at
all.

An address that is merely *printed* — `https://github.com/…/pull/12` at the end
of a `git push`, a URL in a stack trace, one in an agent's answer — is text.
Nothing finds it, nothing underlines it, nothing opens it. That is most of the
addresses anybody sees in a terminal, and every other terminal on this platform
finds them.

The convention asked for is Terminal.app's and iTerm2's: hold ⌘ and the link
under the pointer is underlined and the pointer is a hand; ⌘-click opens it; a
bare click selects text, as it does over every other character.

## Decisions

### 1. Addresses are found in a row's cells, in the Kit

`TerminalLine.webAddresses()` — a scan over the row's cells that returns, for
each address, the columns it spans and the `URL`. Over the cells and not over
`line.text`, because a wide character before the address puts the text one
index behind the columns, and the columns are what the underline and the hit
test need. The scan skips wide trailers, joins the remaining characters, and
maps every text offset back to the column it came from.

**The rule for where an address is**: it begins at `http://`, `https://` or
`mailto:` and runs until whitespace, a quote, or an angle bracket. Trailing
`.`, `,`, `;`, `:`, `!`, `?` are dropped — a URL at the end of a sentence does
not carry the full stop. A trailing `)` is dropped only when the run has no
matching `(` inside it, so a Wikipedia address survives and one written
`(see https://…)` does not carry the bracket. `<https://…>` is a common way to
quote an address and comes out without the brackets.

*Ruled out: `www.` without a scheme, and bare domains.* Every rule for those
also matches `README.md`, a version number, or a package name, and an
underline that lies is worse than one that is missing. A scheme is the one
thing every address a person means to open has.

*Ruled out: `file://`.* What it would open is the Finder or the editor, and the
pane already has `abydos <file>` and ⌘-click on a path in the editor for that.
Not now; the finder is one table if it is wanted.

### 2. ⌘ is the modifier, for the underline and for the open

`hoveredLink` — today an id set on every pointer move — becomes a *range*:
the row, the columns and the URL under the pointer, set only while ⌘ is held
and cleared the moment it is not. The pointer resting on a page draws nothing
and the cursor is the I-beam it is over any text; ⌘ turns both on, and that is
how the reader tells a link from a word that happens to look like one.

Two events feed it. `mouseMoved`, which already runs, reads
`event.modifierFlags` and does the lookup only when ⌘ is in them. And a
`flagsChanged` override, so that ⌘ pressed over a link with the pointer still
draws the underline without a nudge — the gesture is "hold ⌘ and look", and
looking does not move the pointer. `flagsChanged` reaches the view only while it
is first responder; a pane that does not have the keyboard still gets the
underline on the next pointer move, which is the moment somebody is about to
click anyway.

**One row per event.** The lookup finds the address under the pointer's row
only: a marked link by the cell's id first — the program said what it meant,
and a found address inside a marked run defers to it — and otherwise the
row's `webAddresses()`. That is one line scanned per pointer move under ⌘, and
never the scrollback. *Ruled out: scanning every visible row on every frame to
underline all links at once*, which is what a browser does and what a
terminal drawing sixty frames a second of a build log cannot afford; the
underline says "this one, under the pointer", which is all a click needs.

### 3. ⌘-click opens; a bare click selects

`mouseDown` opens the hovered link when ⌘ is held and there is one, and not
otherwise. **A bare click over a marked link no longer opens it.** It was the
one place in the pane where starting a selection did something else, and a
selection that opened a browser is a trap sprung on exactly the text somebody
wanted to copy. Nothing said so in a report; it is what the convention asked
for implies, and it is written here so it is a decision and not a side effect.

**⌘-click wins over a program tracking the mouse.** A pane inside `tmux` with
`mouse on` is a program tracking the mouse, and it is where most of this
project's addresses appear. iTerm2 keeps ⌘-click for itself in that case and
so does this: a ⌘-click over a link opens it and is not forwarded; a ⌘-click
over anything else goes where it went before.

### 4. The underline is drawn by both renderers, from the range

Both renderers get the hovered range and draw a rule under those columns of
that row, in the row's foreground colour, at the underline offset each already
uses for SGR underline. The GPU path replaces its `isLinked` test on the
hovered *id* with a test on the range; the CoreGraphics path gains the pass it
never had, after the rows, in `drawMarked`. The GPU renderer's current
underline on bare hover goes, because bare hover draws nothing under the
convention, and it was one renderer's behaviour rather than the pane's.

### 5. Driving, and no browser

`--terminal-link <row>:<column>` puts the pointer on that cell with ⌘ held, as
the events would, and prints `LINK row= columns= url= underlined=` — the range
found, the address, and whether the renderer in use drew the rule. A second
form, `--terminal-link <row>:<column>:click`, presses ⌘-click there and prints
what would have opened. **A driven run never opens a browser**: `mouseDown`
hands the URL to a `LinkOpener` that on a driven run prints instead of calling
`NSWorkspace`, the way the apply step of the compare page is refused on one.
The address is put into the pane with `--send-bytes`, wrapped so that one
lands on a row with a wide character before it.

## What was measured, 2026-09-10

Every run is `--terminal-link <row>:<column>` on a scratch project, the pane
inside this machine's own `tmux`, an address put there with `--send-bytes` —
one after an emoji, one in a sentence with brackets — and the report read back.
The pane's engine was ours; a picture beside each run shows the rule.

| Case | Cell | Result |
| --- | --- | --- |
| after a wide character, GPU renderer | 0:5 | `columns=3…41`, the address, `marked=false` |
| the same, CoreGraphics renderer | 0:5 | the same range, `renderer=coregraphics`, the rule in the picture |
| brackets: `(see https://…/Diff_(computing)).` | 1:12 | `columns=5…50`, `…Diff_(computing)` — the address's bracket kept, the sentence's dropped |
| a cell after the address | 0:46 | `none` |
| ⌘-click, through `mouseDown` | 0:5:click | `opened=1 selecting=false`, `LINK would open …`, no browser |
| a bare click over the same link | 0:5:bare | `opened=0 selecting=true` |
| a program tracking the mouse (`CSI ?1002 h` printed first) | 0:5:click | `tracking=true opened=1 selecting=false` |
| a link the program marked (OSC 8 around `the docs`) | 0:7 | `columns=4…11`, the marked address, `marked=true` |
| an address of 165 characters in a pane 120 wide | 0:5 | `columns=0…119`, the address cut at the row's end |

The emoji is the reason the finder is over the cells: the address after it
begins at column 3, and a range found in the row's text would have said 2.

**The open question, decided: a wrapped address is two rows, and the design
says so.** The last run is the case. An address longer than the pane wraps,
the finder sees the first row and offers that much, and a ⌘-click on it opens
a truncated address. Joining the rows would need the finder to know the row was
*soft*-wrapped — that the program wrote past the right edge rather than
printing a newline — and the emulator does not record that on a line
(`TerminalLine` has no such flag), so the join cannot be made honestly: a row
that merely ends in an address and a row that continues one look the same. The
flag is a small addition to the emulator and to the Ghostty reader both, and
the join is a few lines on top of it; it is a change of its own, filed when a
wrapped address turns out to be common in what agents print. Until then the
underline stops where the row does, which is at least where the address it
offers stops.

## Release note

> **Web addresses in the terminal open on ⌘-click.** Hold ⌘ over an address
> in a pane — one a program printed, or one it marked as a link — and it is
> underlined and the pointer is a hand; ⌘-click opens it in the browser. A
> bare click selects text as it does everywhere else, which it did not over a
> marked link before. The same in the GPU and the CoreGraphics renderer, and
> through `tmux` with the mouse on.
