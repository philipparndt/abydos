## 1. The entries

- [x] 1.1 `CardCommand` for the name, last in `commands(for:in:)` for every state; a test per state that the last entry copies the name.
- [x] 1.2 The Writing sentence from the missing artifacts in schema order, with prose joining; tests for one, two and three missing, and that Ready still offers apply and not this.

## 2. The menu

- [x] 2.1 The card menu shows the new entries — a separator before *Copy name* — and the copy toast says which was copied.

## 3. Proving it

- [x] 3.1 Driven, on a scratch copy of this board: a change with only a proposal offers *Copy “write the design, the spec delta and the tasks”* then, after a separator, *Copy name*; an archived change offers *Copy name*; a Ready one *Copy “/opsx:apply”* and *Copy name*. The pasteboard itself is not read by a verb; the string an entry copies is what the unit tests check.

## 4. Finishing

- [x] 4.1 Say it in the release notes: the paragraph is in the design.
- [x] 4.2 `make test` and `make warnings`, both clean, by their exit codes. Green 2026-09-09: 4381 tests in 558 suites, exit 0, load 12 at the end of the run; `make warnings` exit 0.

Nothing here makes a `.abydos/backlog/spec/*.md` file untrue: that backlog is
gone and its account is `openspec/specs`, where the `openspec-board` spec is
what this change adds to.
