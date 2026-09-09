## 1. The entries

- [ ] 1.1 `CardCommand` for the name, last in `commands(for:in:)` for every state; a test per state that the last entry copies the name.
- [ ] 1.2 The Writing sentence from the missing artifacts in schema order, with prose joining; tests for one, two and three missing, and that Ready still offers apply and not this.

## 2. The menu

- [ ] 2.1 The card menu shows the new entries — a separator before *Copy name* — and the copy toast says which was copied.

## 3. Proving it

- [ ] 3.1 Driven: a Writing card missing tasks prints *write the tasks*; an Archived card prints *Copy name* and copying puts the name on the pasteboard.

## 4. Finishing

- [ ] 4.1 Say it in the release notes.
- [ ] 4.2 `make test` and `make warnings`, both clean, by their exit codes.

Nothing here makes a `.abydos/backlog/spec/*.md` file untrue: that backlog is
gone and its account is `openspec/specs`, where the `openspec-board` spec is
what this change adds to.
