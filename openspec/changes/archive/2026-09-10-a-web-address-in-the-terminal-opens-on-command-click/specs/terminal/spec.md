# Terminal

## ADDED Requirements

### Requirement: A web address in a pane is a link under ⌘

The terminal SHALL treat an address printed in a pane — beginning with
`http://`, `https://` or `mailto:` and running to whitespace, a quote or an
angle bracket, without trailing sentence punctuation and without a closing
bracket the address did not open — as a link, and SHALL treat a hyperlink a
program marked with OSC 8 as one, the marked address winning where both apply.
While ⌘ is held and the pointer is over a link, the terminal SHALL underline
the link's cells in both renderers and show a hand; without ⌘ it SHALL draw
nothing and show the I-beam. ⌘-click over a link SHALL open the address and
SHALL NOT start a selection nor be forwarded to a program tracking the mouse; a
bare click over a link SHALL select text as over any other character. An
address without a scheme SHALL NOT be a link. A driven run SHALL print what a
⌘-click would open and SHALL NOT open it.

Feedback of 2026-09-10: ⌘ over a link should underline it and a click open it in
the browser, as Terminal.app and iTerm2 do. The terminal knew only marked links,
opened those on a bare click, and underlined them in one renderer.

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

#### Scenario: a bare click over a marked link

- **GIVEN** a program that marked a run of cells as a hyperlink
- **WHEN** the run is clicked without ⌘
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
