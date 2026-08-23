## 1. What ⌃C asks for

- [x] 1.1 **There is no signal to choose between**, which reading the code
      settled: a `TerminalPane(readOnly:)` never launches its `PseudoTerminal`,
      so the debugger's console owns no process. The design's original question —
      `SIGINT` to the group or `0x03` down the pty — was about a pty that does
      not exist.
- [ ] 1.2 ⌃C makes the request the Stop button makes, through the same path, so
      the two cannot drift into two opinions about what stopping means.
- [ ] 1.3 Whether that is `terminate` or `disconnect`, and whether it differs for
      an attached session, is the Stop button's answer to give — not a second one
      decided here.

## 2. The keyboard

- [ ] 2.1 A console takes first responder, which is the whole mechanism —
      `acceptsFirstResponder` is `runsProcess` today and that is why no key
      arrives.
- [ ] 2.2 Only the interrupt is carried. Everything else is dropped: a pane
      somebody believes is read-only must not quietly deliver what they typed to
      a program that happens to be reading stdin.
- [ ] 2.3 Nothing changes for a shell or a Run console, both of which have a pty
      and both of which already take ⌃C — `runCommand` builds a real terminal.
      The regression to look for is one of those losing the keyboard.
- [ ] 2.4 A console whose program has exited does nothing and says nothing.

## 3. Watched

- [ ] 3.1 Against a project under the scratchpad, never a real checkout.
      `java/hot-swap` in the examples prints a line a second and is the program
      this was reported against — copy it and press ⌃C.
- [ ] 3.2 The trapping case: a small program that catches the interrupt, prints
      that it caught it, and carries on. Twice, to see nothing escalate.
- [ ] 3.3 A shell tab, to see it unchanged — the regression this could cause.
- [ ] 3.4 A driven check if one can be written. `--tree`-style verbs exist for
      the navigator; whether a key can be delivered to a panel pane in a driven
      run is worth finding out, since "the console has the keyboard" is exactly
      the sort of claim a person confirms once and nobody checks again.

## 4. Finishing

- [ ] 4.1 Answer the design's other two open questions with what was built:
      whether the console takes the keyboard on start or only on a click, and
      what — if anything — this implies for the debugger's console, which is a
      `DebugPane` and stops by another path.
- [ ] 4.2 `make test` and `make warnings`, both clean, and their exit codes read
      rather than their output.

No `.abydos/backlog/spec/*.md` file is made untrue: that backlog is gone. What
this changes is `openspec/specs/debug-sessions/spec.md`, in the delta beside this
file — not `terminal`, which was where this was first filed on the belief that a
console had a pty behind it.
