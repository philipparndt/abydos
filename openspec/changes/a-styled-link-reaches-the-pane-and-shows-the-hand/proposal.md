## Why

The maintainer, 2026-09-11, with a screenshot from Ghostty of Claude Code's
*"Pushed to fix/admin-logo-and-docs-redirect, created PR #211"*, the `#211`
underlined: *"it was possible in ghostty to click on 'links' from claude like
the PR in this example … we already support http links but this is something
differently (styled link)"* — and, a moment later, *"would be also nice to have
a different mouse pointer over them"*.

The underline is an OSC 8 hyperlink: the program brackets the text it wants
clickable with the address it means. This terminal already reads OSC 8 in both
engines — a cell carries the id of the address it belongs to — and since
2026-09-10 a ⌘-click opens a marked link. Nothing was missing at the pane. The
links never reached it, for two separate reasons, both measured on 2026-09-11:

- **Through tmux, tmux drops them.** Claude Code decides whether to write
  OSC 8 from `TERM_PROGRAM`, and inside tmux 3.4 or newer it does write them
  (read out of the installed 2.1.268 binary). tmux then forwards a hyperlink
  only to a client whose terminal declared the `hyperlinks` feature, and the
  client this app starts declares `-T RGB` and nothing else; the live client
  on this machine reports `bpaste,ccolour,clipboard,cstyle,extkeys,focus,RGB,title`.
  A scratch tmux server driven through a pty: `-T RGB` forwarded 0 of 2
  OSC 8 sequences, `-T RGB,hyperlinks` forwarded both, rewritten as
  `ESC ] 8 ; id=tmux1 ; url ESC \` — a form the emulator's parser already
  splits correctly.
- **In a bare pane, Claude Code never writes them.** `TERM_PROGRAM=Abydos` is
  on nobody's list; the binary's rule is ghostty, kitty, iTerm, Hyper,
  alacritty, JetBrains, Windows Terminal, tmux ≥ 3.4 — or `FORCE_HYPERLINK`
  set, which is the convention of the `supports-hyperlinks` library many
  tools use.

And the pointer: the hand and the underline appear only while ⌘ is held, for a
marked link and a printed address alike. A marked link is one the program has
declared; asking for ⌘ before saying so is asking twice.

There is no originating `.abydos/backlog` item: this comes from a direct
report, 2026-09-11.

## What Changes

- **The tmux client declares `hyperlinks`** beside `RGB`, so tmux forwards a
  program's OSC 8 to the pane instead of stripping it.
- **A bare pane sets `FORCE_HYPERLINK=1`**, so a program that asks the
  convention's question gets the honest answer: this terminal shows them.
- **A marked link shows the hand and the underline on plain hover.** A
  printed address still waits for ⌘, as does the click for both: a bare click
  goes on selecting, and a program tracking the mouse is not stolen from.
- **The driven `--terminal-link` step can hover without ⌘**, so the rule is a
  line a run prints and not a picture somebody remembers.

## Capabilities

### Modified Capabilities

- `terminal`: the requirement *A web address in a pane is a link under ⌘*
  gains the hover rule for a marked link; a new requirement says what the
  pane does so a styled link reaches it at all — through tmux and without.

## Impact

- **AbydosKit**: `TmuxMirror.attachArguments` (`-T RGB,hyperlinks`) and
  `PseudoTerminalEnvironment` (`FORCE_HYPERLINK`), with their tests in
  `TmuxMirrorTests`, `PaintedPairTests` and `PseudoTerminalWriteTests`.
- **AbydosApp**: `TerminalView+Mouse.swift` (`updateHoveredLink`,
  `link(atWindowPoint:)`), `LaunchOptions+Parse.swift` and
  `BottomPanel+Driving.swift` for the hover mode of `--terminal-link`.
- **The spec**: `openspec/specs/terminal/spec.md`, the link requirement and
  the scenario that names tmux's client features.
