## 1. What ⌃C asks for

- [x] 1.1 **There is no signal to choose between**, which reading the code
      settled: a `TerminalPane(readOnly:)` never launches its `PseudoTerminal`,
      so the debugger's console owns no process. The design's original question —
      `SIGINT` to the group or `0x03` down the pty — was about a pty that does
      not exist.
- [x] 1.2 `DebugSession.stop()`, which is exactly what the toolbar's Stop calls
      (`toolbar.onStop = { self?.session.stop() }`). One path, so the key and the
      button cannot drift into two opinions about stopping.
- [x] 1.3 It is `disconnect` — `stop()` sets the state and then
      `client.disconnectThenStop`, with a long note about why the adapter is
      drained rather than killed. Inherited rather than re-decided, which is the
      point of going through the same call.

## 2. The keyboard

- [x] 2.1 `acceptsFirstResponder` becomes `runsProcess || onInterrupt != nil`.
      **Keyed on having something to stop**, which is what keeps this to the
      debugger's console: the two streaming-log panes and the devcontainer's
      *preparing* terminal are read-only too, set no `onInterrupt`, and behave
      exactly as they did.
- [x] 2.2 `keyDown` returns early for a view that runs no process, carrying the
      interrupt and dropping everything else. `TerminalKeys.isInterrupt` is the
      predicate, in `AbydosKit` where it can be tested — ⌘C is Copy and ⌥⌃C is a
      different keystroke, and a console that stopped the program on a copy would
      be a trap.
- [x] 2.3 Nothing changes for a shell or a Run console: both have `runsProcess`
      true, so neither the early return nor the new half of
      `acceptsFirstResponder` applies to them.
- [x] 2.4 Guarded on `session.isActive`. Without it, ⌃C over a finished session
      would send a second `disconnect` and print its ending twice.

## 3. Watched

- [x] 3.1 Watched against `java/hot-swap`, the program this was reported about:
      Debug, click the console, ⌃C — the session stops, the output stays and the
      tab stays open.
- [x] 3.2 **Dropped with the framing that needed it.** It was written when this
      was going to send a signal, and it does not: ⌃C makes a DAP `disconnect`,
      so "a program that traps the interrupt" is not a case the spec claims
      anything about any more. What replaced it is a sentence rather than a test
      — the design says plainly that no signal is sent and that a `SIGINT`
      handler will not run — and a test cannot check that somebody was told.
- [x] 3.3 A shell tab, unchanged: `sleep 5` in a terminal window, ⌃C, exits.
      Which is the regression this could have caused and did not — `runsProcess`
      is true there, so neither the early return in `keyDown` nor the new half of
      `acceptsFirstResponder` applies.
- [x] 3.4 It can, and `--debug-interrupt <seconds>` is it:

          INTERRUPT: firstResponder=true active before=true after=false

      **A key delivered where a person delivers it**, not `session.stop()` called
      and the key assumed — `firstResponder=true` is the half that was broken and
      the only part a driver can prove. Built on the pattern
      `pressKeyForTesting` already uses in the navigator: a real `NSEvent`
      through `keyDown`.

## 4. Finishing

- [x] 4.1 **Click-only**, decided by the person who will live with it. The
      console does not take the keyboard when a session starts: doing so would
      move it away from the editor on every Debug press, which is the more
      annoying failure and the harder one to trace back to its cause. ⌃C is aimed
      at the console by clicking it, as any pane is.

      The other question answered itself: the debugger's console *is* the pane
      this change is about, so there is nothing left over for it.
- [x] 4.2 Both clean, exit codes read: `make test` 0 over 3,201 tests in 426
      suites, `make warnings` 0.

No `.abydos/backlog/spec/*.md` file is made untrue: that backlog is gone. What
this changes is `openspec/specs/debug-sessions/spec.md`, in the delta beside this
file — not `terminal`, which was where this was first filed on the belief that a
console had a pty behind it.
