## 1. Measure

- [x] 1.1 A test over every bundled scheme's `terminal` section: the WCAG contrast ratio of each ANSI colour against the light and the dark ground, printing the pairs under 4.5:1 and under 3:1 — so the report becomes a list before anything is changed. `TerminalContrastTests`, over `SchemeContrast` in the kit: 98 pairs before the fix, 88 of them light.
- [x] 1.2 A screenshot in the light theme with a prompt, a coloured `ls` and a diff, for each scheme, next to the same in the dark theme. Taken 2026-09-09 with a driven run — `--terminal --theme <theme> --terminal-scheme <palette> --send-bytes <a palette card, ls -G, git status and diff>` — before and after, for every palette on the light ground and the default on the dark; what they showed is in the design. Not committed: sixteen pictures of four hundred kilobytes each, reproducible from those flags.
- [x] 1.3 Write into the design which colours fail, on which schemes, and whether the failure is the bright half reused from the dark table.

## 2. Decide

- [x] 2.1 The floor: 4.5:1 for every colour, or 3:1 for the eight that are meant to read as dim. Decided in the design from what 1.1 shows, with what each choice would recolour.

## 3. Fix

- [x] 3.1 Light-mode ANSI tables for the schemes that fail, chosen against their light ground; the schemes that already pass untouched. 47 light values and 9 dark ones moved, each keeping its hue; the table of the dark ones is in the design.
- [x] 3.2 The test from 1.1 turned into a claim at the chosen floor, so a scheme added later is held to it.
- [x] 3.3 `terminal.floor` in the scheme format — parsed, refused when not a number, documented in the README — and the measurement holds a palette to what it promises, the dim colour one step below.
- [x] 3.4 `wcag-level-aaa.json`: the default palette's hues at 7:1 against every editor ground, light and dark, promising `"floor": 7`; `--terminal-scheme <id>` on a driven run, so it and the other palettes can be photographed.

## 4. Proving it

- [x] 4.1 The screenshots from 1.2 taken again, and read by somebody in the light theme. Read; the design says what was seen, including the one thing that is still a trade.

## 5. Finishing

- [x] 5.1 Say it in the release notes: the light terminal was unreadable and which schemes changed. The paragraph is in the design under "Release note", for the next `docs/release-notes-<version>.md`, which is written when a release is cut.
- [x] 5.2 `make test` and `make warnings`, both clean, by their exit codes. Green 2026-09-09: 4364 tests in 556 suites, exit 0, load about 21 at the end of the run; `make warnings` exit 0, no warnings.

Nothing here makes a `.abydos/backlog/spec/*.md` file untrue: that backlog is
gone and its account is `openspec/specs`, where the `terminal` spec is what this
change adds to.
