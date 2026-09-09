## 1. Measure

- [ ] 1.1 A test over every bundled scheme's `terminal` section: the WCAG contrast ratio of each ANSI colour against the light and the dark ground, printing the pairs under 4.5:1 and under 3:1 — so the report becomes a list before anything is changed.
- [ ] 1.2 A screenshot in the light theme with a prompt, a coloured `ls` and a diff, for each scheme, next to the same in the dark theme.
- [ ] 1.3 Write into the design which colours fail, on which schemes, and whether the failure is the bright half reused from the dark table.

## 2. Decide

- [ ] 2.1 The floor: 4.5:1 for every colour, or 3:1 for the eight that are meant to read as dim. Decided in the design from what 1.1 shows, with what each choice would recolour.

## 3. Fix

- [ ] 3.1 Light-mode ANSI tables for the schemes that fail, chosen against their light ground; the schemes that already pass untouched.
- [ ] 3.2 The test from 1.1 turned into a claim at the chosen floor, so a scheme added later is held to it.

## 4. Proving it

- [ ] 4.1 The screenshots from 1.2 taken again, and read by somebody in the light theme.

## 5. Finishing

- [ ] 5.1 Say it in the release notes: the light terminal was unreadable and which schemes changed.
- [ ] 5.2 `make test` and `make warnings`, both clean, by their exit codes.

Nothing here makes a `.abydos/backlog/spec/*.md` file untrue: that backlog is
gone and its account is `openspec/specs`, where the `terminal` spec is what this
change adds to.
