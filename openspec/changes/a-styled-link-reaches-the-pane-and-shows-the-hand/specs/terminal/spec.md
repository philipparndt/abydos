# Terminal

## ADDED Requirements

### Requirement: A styled link a program writes reaches the pane

The terminal SHALL start its tmux client declaring the `hyperlinks` terminal
feature beside `RGB`, so that a hyperlink a program marks with OSC 8 inside
that tmux is forwarded to the pane rather than stripped. A pane's environment
SHALL default `FORCE_HYPERLINK` to `1` — deferring to a value already set — so
that a program asking the convention's question in a pane that is not a tmux
client is told this terminal shows hyperlinks. The terminal SHALL NOT claim to
be another terminal to obtain this: `TERM_PROGRAM` stays `Abydos`.

Reported 2026-09-11 with a screenshot from Ghostty: Claude Code's `#211` was a
link there and plain text here. Measured the same day: tmux 3.7c forwarded 0 of
2 OSC 8 sequences to a client started with `-T RGB` and 2 of 2 to one started
with `-T RGB,hyperlinks`; and the installed Claude Code writes OSC 8 for
`TERM_PROGRAM=tmux` 3.4 or newer or for `FORCE_HYPERLINK` set, and not for
`TERM_PROGRAM=Abydos`.

#### Scenario: a styled link through tmux

- **GIVEN** a pane inside the tmux this terminal started
- **WHEN** a program in it writes `ESC ] 8 ; ; https://github.com/o/r/pull/211 ESC \ #211 ESC ] 8 ; ; ESC \`
- **THEN** the cells holding `#211` carry that address, and tmux's client
  features include `hyperlinks`

#### Scenario: tmux's own parameter

- **GIVEN** a hyperlink tmux forwarded as `ESC ] 8 ; id=tmux1 ; https://example.org ESC \`
- **WHEN** the emulator reads it
- **THEN** the cells that follow carry `https://example.org`, and the id is not
  part of the address

#### Scenario: a bare pane's environment

- **GIVEN** a pane started with no `FORCE_HYPERLINK` in the app's environment
- **WHEN** its shell is started
- **THEN** it finds `FORCE_HYPERLINK=1` and `TERM_PROGRAM=Abydos`

#### Scenario: somebody said no

- **GIVEN** `FORCE_HYPERLINK=0` in the environment the pane is made from
- **WHEN** its shell is started
- **THEN** it finds `FORCE_HYPERLINK=0`, as it was

## MODIFIED Requirements

### Requirement: A web address in a pane is a link under ⌘

The terminal SHALL treat an address printed in a pane — beginning with
`http://`, `https://` or `mailto:` and running to whitespace, a quote or an
angle bracket, without trailing sentence punctuation and without a closing
bracket the address did not open — as a link, and SHALL treat a hyperlink a
program marked with OSC 8 as one, the marked address winning where both apply.
While the pointer is over a link the program marked, the terminal SHALL
underline the link's cells in both renderers and show a hand, whether or not ⌘
is held, and SHALL offer the link's address as a tooltip over those cells,
since the text of a styled link says nothing about where it goes; a printed
address, being its own text, gets no tooltip. While ⌘ is held and the pointer is over a printed address, the
terminal SHALL underline it and show a hand; without ⌘ it SHALL draw nothing
over a printed address and show the I-beam. ⌘-click over a link of either kind
SHALL open the address and SHALL NOT start a selection nor be forwarded to a
program tracking the mouse. A plain press on a link the program marked SHALL be
held until its release: released within a cell of where it landed it is a
click and SHALL open the address, forwarding neither press nor release to a
program tracking the mouse and selecting nothing; a press that travels a cell
first SHALL become the selection, or the forwarded press, it would have been on
any other cell, and SHALL open nothing. Shift held SHALL make any press a
selection. A bare click over a printed address SHALL select text as over any
other character. An address without a scheme SHALL NOT be a link. A driven run
SHALL print what a click would open and SHALL NOT open it, and SHALL be able
to report the hover with no modifier held and a press that drags.

Feedback of 2026-09-10: ⌘ over a link should underline it and a click open it in
the browser, as Terminal.app and iTerm2 do. The terminal knew only marked links,
opened those on a bare click, and underlined them in one renderer. Feedback of
2026-09-11: a link the program styled should show a different pointer — the
program has already said it is one. And the same day, once it did: *"this is
unintuitive as it already underlines/hovers"* — a hand that then needs ⌘ to
click. The bare click of 2026-09-10 was removed for springing on text somebody
was about to select; the release decides now, so a drag still selects.

#### Scenario: an address a program printed

- **GIVEN** a pane in which `git push` has printed `https://github.com/example/repo/pull/12`
- **WHEN** ⌘ is held and the pointer rests on it
- **THEN** exactly those characters are underlined, the pointer is a hand, and
  a ⌘-click opens that address

#### Scenario: the full stop after it

- **GIVEN** a line reading `See https://example.org/page.`
- **WHEN** ⌘ is held over the address
- **THEN** the underline ends before the full stop, and the address opened has
  none

#### Scenario: a bracket the address opened, and one it did not

- **GIVEN** `https://en.wikipedia.org/wiki/Diff_(computing)` on one line and
  `(see https://example.org)` on another
- **WHEN** each is under the pointer with ⌘ held
- **THEN** the first keeps its closing bracket and the second does not

#### Scenario: a marked link under the pointer, no ⌘

- **GIVEN** a program that marked `#211` as a hyperlink
- **WHEN** the pointer rests on it with no modifier held
- **THEN** the four cells are underlined in both renderers, the pointer is a
  hand, and a tooltip over those cells reads the address

#### Scenario: no tooltip over a printed address

- **GIVEN** the pointer over `https://example.org/x` a program printed, ⌘ held
- **WHEN** it rests there
- **THEN** the address is underlined and no tooltip is offered

#### Scenario: a plain click over a marked link

- **GIVEN** a program that marked `#211` as a hyperlink
- **WHEN** it is pressed and released without ⌘, the pointer staying within a
  cell
- **THEN** the address opens on the release, nothing is selected, and a
  program tracking the mouse receives neither press nor release

#### Scenario: a drag that begins on a marked link

- **GIVEN** the same marked link
- **WHEN** it is pressed without ⌘ and the pointer travels two cells before
  the release
- **THEN** nothing opens and the text from the press to the release is
  selected — or, when a program tracks the mouse, the press and the drag are
  forwarded to it as they would be from any cell

#### Scenario: a bare click over a printed address

- **GIVEN** the pointer over an address a program printed
- **WHEN** it is clicked without ⌘
- **THEN** nothing opens and a selection begins, as over any text

#### Scenario: without ⌘

- **GIVEN** the pointer resting on a printed address
- **WHEN** ⌘ is not held
- **THEN** nothing is underlined and the pointer is the I-beam

#### Scenario: inside tmux with the mouse on

- **GIVEN** a pane whose program tracks the mouse
- **WHEN** a link in it is ⌘-clicked
- **THEN** the address opens and the program receives no click

#### Scenario: a driven run

- **GIVEN** a driven run with an address in a pane
- **WHEN** its `--terminal-link` step ⌘-clicks the address
- **THEN** the run prints the address that would have opened, and no browser
  opens

#### Scenario: a driven hover without ⌘

- **GIVEN** a driven run with a marked link and a printed address in a pane
- **WHEN** its `--terminal-link` step hovers each with `hover`
- **THEN** the run reports the marked link underlined and the printed address
  not

#### Scenario: a driven click and drag without ⌘

- **GIVEN** a driven run with a marked link in a pane
- **WHEN** its `--terminal-link` step presses and releases it with `bare`, and
  in another run presses and travels with `drag`
- **THEN** the first reports one opening and nothing selected, the second
  nothing opened
