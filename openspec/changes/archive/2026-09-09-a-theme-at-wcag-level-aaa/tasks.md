## 1. Measure

- [x] 1.1 `SchemeContrast` walks the app half: text roles against their grounds, dim roles one step down, syntax kinds against the editor's ground, floor from `app.floor`. A test over the bundled library prints the shortfalls; the table is in the design.
- [x] 1.2 `Scheme.read` takes `app.floor`, refusing a non-number as it does for the terminal; the README says so.

## 2. Fix

- [x] 2.1 Every shipped theme's failing values moved in place, hue kept; the dark ones listed in the design. Twenty values: eighteen light, two dark.
- [x] 2.2 `wcag-level-aaa.json` gains an `app` section at 7:1 from the blue theme's hues, `"floor": 7` on both halves; the id derives its stored names, so no `stored` block. Worst text role 7.11:1, worst syntax kind 7.10:1.

## 3. Proving it

- [x] 3.1 The measurement passes for every theme at its promised floor.
- [x] 3.2 Screenshots of the editor with code, comments and a changed file in the sidebar: each theme's light half, and the AAA theme in both — read for what the darkening did to the syntax colours' distinctness. Read; the design says what was seen.
- [x] 3.3 `BundledSchemeTests`' list of ids grows by nothing — the AAA file already exists — and it reads; the one pinned value the recolouring moved, the abydos light caret, is updated with a note — as is `AppearanceTests`' list of four families, now five.

## 4. Finishing

- [x] 4.1 Say it in the release notes: the paragraph is in the design.
- [x] 4.2 `make test` and `make warnings`, both clean, by their exit codes. Green 2026-09-09: 4376 tests in 558 suites, exit 0, load 41 at the end of the run; `make warnings` exit 0.

Nothing here makes a `.abydos/backlog/spec/*.md` file untrue: that backlog is
gone and its account is `openspec/specs`, where `themes` is new.
