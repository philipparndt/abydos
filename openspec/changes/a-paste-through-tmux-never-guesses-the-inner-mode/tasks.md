## 1. The decision

- [x] 1.1 `TmuxPaste.plan(text:throughTmux:tmuxAccepted:bracketedPaste:)` in the
      Kit, returning `.tmuxTook` or `.write(String)`: raw text for a tmux client
      tmux did not accept, markers only for a non-tmux client whose mode is on.
- [x] 1.2 Tests, as claims: `aTmuxClientTmuxTookIsWrittenNothing`,
      `aTmuxClientTmuxRefusedIsWrittenRawTextWithNoMarker`,
      `aPlainPaneWithBracketedPasteOnGetsTheMarkers`,
      `aPlainPaneWithoutItGetsTheRawText`.

## 2. The retry and the wiring

- [x] 2.1 The tmux paste — `session(forClient:)` then `TmuxMirror.paste` —
      retried a bounded few times, a few milliseconds apart, before it is
      failed.
- [x] 2.2 `TerminalView.paste`/`sendPaste` route through `TmuxPaste.plan`: the
      branch that used to guess writes what the plan says, and writes no markers
      on a failed tmux client.

## 3. Proving it

- [x] 3.1 `TmuxPasteTests` gains the leak's shape against a real tmux: a client
      with bracketed paste on over an inner program with it off, and a fallback
      paste whose bytes carry no marker.
- [x] 3.2 Driven: a paste into a real tmux pane in a scratch session comes out
      clean; recorded in the design. `--paste-terminal` into `cat -v`, no
      marker on the screen.

## 4. Before finishing

- [x] 4.1 Say it in the release notes: the paragraph is in the design.
- [x] 4.2 `make test` and `make warnings`, both clean, by their exit codes;
      `openspec validate` on the change. Green 2026-09-10: 4,439 tests in 567
      suites, exit 0 (a first run lost the flaky free-port test
      `aFreePortIsFoundAndIsNotOpen`, a TOCTOU race, green alone and on rerun);
      `make warnings` exit 0; the change valid.

Nothing here makes a `.abydos/backlog/spec/*.md` file untrue: that backlog is
gone and its account is `openspec/specs`, where the `terminal` spec is what
this change adds to.
