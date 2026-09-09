## 1. The write

- [ ] 1.1 `BacklogItem.unticking(line:in:)` and `untick(line:in:)`: the mirror of `ticking`, refusing a line that does not read as a ticked step with the expected text, byte for byte otherwise. Tests turned around from the tick's: a plain untick, the bullet and indentation kept, the final newline kept or absent, a moved line refused, an already-open line refused.

## 2. The tip

- [ ] 2.1 After a tick, the tip keeps the ticked row for a beat — drawn ticked and dimmed with *Undo* at its end — and a click on it unticks through 1.1; the next re-read or the pointer leaving drops it.
- [ ] 2.2 A refused untick says the task has moved and shows the file as it is, as a refused tick does.

## 3. The keyboard

- [ ] 3.1 The board pane owns an `NSUndoManager`, registers each tick's reversal named *Tick*, and answers ⌘Z and *Undo Tick* while it or the tip has the keyboard; registrations are dropped when the project changes.

## 4. Proving it

- [ ] 4.1 The tip's driving verb gains an `undo` step, and a run ticks, undoes, and prints the line reading `[ ]` with the same text.

## 5. Finishing

- [ ] 5.1 Say it in the release notes.
- [ ] 5.2 `make test` and `make warnings`, both clean, by their exit codes.

Nothing here makes a `.abydos/backlog/spec/*.md` file untrue: that backlog is
gone and its account is `openspec/specs`, where `open-tasks-on-a-card` is what
this change adds to.
