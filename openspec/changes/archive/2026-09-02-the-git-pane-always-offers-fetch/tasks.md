## 1. The control

- [x] 1.1 Replace the repository row's symbol `secondaryAction` with a titled one reading `Fetch`, drawn with the library from `the-zoom-reaches-every-control`.
- [x] 1.2 Draw no secondary control where the repository has no remote, and drop the no-remote branch from `refreshPressed()`.
- [x] 1.3 Put the local re-read on the row's context menu beside the verbs already there.
- [x] 1.4 Rename `pressRefreshGlyphForTesting` for what it presses now, and keep the driver step working.

## 2. Proving it

- [x] 2.1 Driven on a scratch repository one commit ahead: the row's verb reads `Push` and a `Fetch` control is on the row beside it.
- [x] 2.2 Driven with no remote: no secondary control, and the re-read is on the menu. Driven on 2026-09-02: `no remote · nothing to press · second none`; the pinned row has no driven menu step, so the re-read is read off the menu the row builds, `Read the Repository Again`.

## 3. Finishing

- [x] 3.1 Say the removal in the release notes: the glyph is gone and what took its place.
- [x] 3.2 `make test` and `make warnings`, both clean, both by their exit codes. Green on the reporter's machine, 2026-09-02: 4004 tests in 511 suites passed after 81.4 s with 2 known issues, exit 0. Every run here the same afternoon was red on one load-bound give-up test at loads of 16 to 56 over 14 cores.

Nothing here makes a `.abydos/backlog/spec/*.md` file untrue: that backlog is
gone and its account is `openspec/specs`, where the delta in this change is what
it makes true.
