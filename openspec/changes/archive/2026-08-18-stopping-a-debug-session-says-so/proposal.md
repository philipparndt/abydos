## Why

Start a Go service under the debugger, stop at a breakpoint, press Stop. The
toolbar says **Finished**. The console says nothing at all, and the goroutine
list still shows `* [Go 1] main.main (Thread 27093656)` as though the program
were still sitting there.

Three faults, one gesture, and they are all in the same eight lines:

    public func stop() {
        client.send("disconnect", arguments: ["terminateDebuggee": true])
        client.stop()
        state = .terminated
        stackFrames = []
        scopes = []
        onMain { self?.onStackChanged?(); self?.onVariablesChanged?() }
    }

**The adapter is killed before it can answer.** `client.stop()` clears the
readability handlers first and then terminates the process, so the `disconnect`
that was just sent is never read and nothing the adapter says afterwards
arrives.

**Corrected by measurement**, because this first said the exit code was what was
being lost. Driven against Delve, a stop produces one more sentence —
`Detaching and terminating target process` — and **no status at all**, because
the program did not exit: Delve killed it. `noteExitCode` parses "has exited with
status N", and that belongs to a program that ends on its own. So what the
premature kill loses on this path is the adapter's last words, not a code; the
code matters on the *other* path, where it already worked and must go on working
once the teardown moves. Both are in the spec, said as what they are.

**The goroutine list is never cleared.** `stackFrames` and `scopes` are emptied;
`threads` is not, anywhere — not here and not in the `terminated`/`exited`
handler. `onThreadsChanged` is not fired either, so even emptying it would leave
the table as it was. The list on screen belongs to a process that has gone.

**And nothing announces the end.** The console carries the session's lifecycle
already — "Building /Users/…/go-service" and Delve's own banner are in the
screenshot — but every word of that is the *adapter* speaking. When the adapter
has nothing to say, or is killed before it can, the console simply stops, and a
log that stops is indistinguishable from one that is waiting.

Reported from `abydos-examples/go-service`, with the picture.

## What Changes

- **Stopping waits for the adapter to answer before killing it**, briefly and
  with a deadline — measured at 0.016 s for Delve, against a deadline of one
  second. What arrives in that window is the adapter's last words, and for a
  program that ended on its own it is also where Delve's exit status is.
- **The goroutine list is cleared when the session ends**, and the table is told
  — on a user-initiated stop and on the adapter's own `terminated`/`exited`,
  which are two paths to the same place and only one of them clears anything
  today.
- **The console says the session ended**, in the app's own words rather than
  waiting for the adapter to volunteer them: that it finished, and the exit code
  when there is one. A run's console is a record of what happened, and "it
  stopped" is part of what happened.
- **A stop that cannot be completed says so** rather than being reported as a
  clean finish. An adapter that will not answer inside the deadline is killed, as
  now, and the console says that is what happened.
- **Not proposed: waiting indefinitely.** The stop button must return. The
  deadline and what it costs are in `design.md`.

## Capabilities

### New Capabilities

- `debug-sessions`: what a debug session leaves behind when it ends — what the
  panes show, what the console says, and what a stop that could not be completed
  reports. **Debugging has no spec page at all**: `run-configurations` covers
  what a project can run and never mentions the debugger, so this is the first
  requirement written about it rather than a change to an existing one. Only what
  this report touches is written; the rest of debugging stays undescribed until
  something else touches it, which is how this repository's other pages grew.

## Impact

- `Sources/AbydosKit/Debug/DebugSession.swift` — `stop()`, the
  `terminated`/`exited` handler, `threads`, `onThreadsChanged`, and
  `noteExitCode(inOutput:)`, which can only work if the output that carries the
  status is still being read.
- `Sources/AbydosKit/Debug/DAPClient.swift` — `stop()` tears down the pipes
  before the adapter has answered; it already carries a `StallWatch` note about
  a half-second busy-wait on the main thread, so anything added here has to be
  weighed against that rather than piled on top of it.
- `Sources/AbydosApp/Panel/DebugPane.swift` — the threads table, and the console
  the end-of-session line goes to.
- `.abydos/backlog/spec/` — **there is no page for debugging.**
  `run-configurations.md` mentions it nowhere, so this adds one rather than
  editing one.
- No new dependency.
