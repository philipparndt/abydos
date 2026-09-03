## 1. The renderer

- [x] 1.1 A `pass` uniform and a `withinCell` varying in `TerminalShaders`; the fragment paints backgrounds inside the cell on pass 0 and glyphs with coverage alpha on pass 1.
- [x] 1.2 `TerminalMetalRenderer` draws the instance buffer twice, once per pass, binding everything else once.

## 2. Proving it

- [x] 2.1 `--metal-shot` with the three marks on screen: whole diamonds in the drawable, where the same shot before showed their left halves.

## 3. Finishing

- [x] 3.1 Say it in the release notes.
- [x] 3.2 `make test` and `make warnings`, both clean, both by their exit codes. Green on the reporter's machine, 2026-09-02: 4004 tests in 511 suites passed after 81.4 s with 2 known issues, exit 0. Every run here the same afternoon was red on one load-bound give-up test at loads of 16 to 56 over 14 cores.

Nothing here makes a `.abydos/backlog/spec/*.md` file untrue: that backlog is
gone and its account is `openspec/specs`, where the `terminal` delta in this
change is what it makes true.
