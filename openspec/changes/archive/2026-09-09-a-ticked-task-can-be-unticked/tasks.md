## 1. The write

- [x] 1.1 `BacklogItem.unticking(line:in:)` and `untick(line:in:)`: the mirror of `ticking`, refusing a line that does not read as a ticked step with the expected text, byte for byte otherwise. Tests turned around from the tick's: a plain untick, the bullet and indentation kept, the final newline kept or absent, a moved line refused, an already-open line refused.

## 2. The tip

- [x] 2.1 After a tick, the tip keeps the ticked row for a beat — drawn ticked and dimmed with *Undo* at its end — and a click on it unticks through 1.1; the next re-read or the pointer leaving drops it.
- [x] 2.2 A refused untick says the task has moved and shows the file as it is, as a refused tick does.

## 3. The keyboard

- [x] 3.1 The board pane owns an `NSUndoManager`, registers each tick's reversal named *Tick*, and answers ⌘Z and *Undo Tick* while it or the tip has the keyboard; `forgetTickUndo()` drops the registrations. **⌘Z itself was not driven**: the manager is reached through the responder chain, which no verb here presses; the untick it calls is the one the *Undo* row calls, and that one was.

## 4. Proving it

- [x] 4.1 `--backlog-untick <card>` after `--backlog-tick`, and a run on a scratch copy of this board ticked task 5.2 of the Java change to 25 of 31 and unticked it: `line 92: - [ ] 5.2 **Measure the build before settling this.**`, the same words.

## 5. Finishing

- [x] 5.1 Say it in the release notes: the paragraph is in the design.
- [x] 5.2 `make test` and `make warnings`, both clean, by their exit codes. Green 2026-09-09: 4381 tests in 558 suites, exit 0, load 12 at the end of the run; `make warnings` exit 0.

Nothing here makes a `.abydos/backlog/spec/*.md` file untrue: that backlog is
gone and its account is `openspec/specs`, where `open-tasks-on-a-card` is what
this change adds to.
