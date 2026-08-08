# Add native Go debugger, fix terminal rendering, audit licences for open source

`41ad7b7a7` · 2026-07-30

Native debugger over DAP, replacing the Delve terminal UI:
- Breakpoints toggle from the editor gutter and persist across runs. They are
  drawn hollow until the adapter verifies them, because a solid marker where
  execution can never stop is a lie.
- Call stack and an expandable variables tree, with children fetched lazily on
  first expansion.
- Continue, pause, step over/into/out, stop; the stopped line is highlighted in
  the editor and jumped to automatically.

Targeting DAP rather than Delve's own API means the same front end will take
other adapters later without a new transport.

Terminal fixes, all found by running real tools:

- Powerline separators vanished. `isGraphemeBase` is false for the Private Use
  Area, so `displayWidth` returned 0 and every separator was merged into the
  previous cell as if it were a combining mark. Only genuine marks and format
  characters are zero-width now. The font was never the problem.
- Colon SGR subparameters (4:3 curly underline, 58:2::r:g:b underline colour)
  parsed as nil and fell back to 0 — SGR "reset everything" — so one styled run
  wiped all attributes. The primary value is now taken before the colon.
- A step appeared where a powerline separator met the next segment: fractional
  cell advances accumulate across a row, leaving hairline seams between run
  backgrounds. Cell metrics round to whole points and run edges are computed
  from the run's end, so neighbours abut exactly.
- tmux drew its status bar near the top until the pane was resized: the grid was
  measured before layout settled, and a full-screen program lays out once at
  whatever size it was told. Launch now waits for a real size.
- Review ran forever at an empty prompt. `--allowedTools` is variadic and
  swallowed the trailing prompt as another tool name; the prompt now comes
  first.

Also adds hover feedback in the project switcher, and "Open in Fork" in the
branch menu when Fork is installed.

Licence audit for open-sourcing: the four vendored grammars were redistributed
without their upstream MIT notices, which the licence requires. Each now carries
its LICENSE, the vendor script copies it automatically, and
THIRD-PARTY-NOTICES.md records every component and its obligations.

163 tests.
