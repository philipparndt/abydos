## Context

The whole of stopping, as it stands:

    public func stop() {
        client.send("disconnect", arguments: ["terminateDebuggee": true])
        client.stop()
        state = .terminated
        stackFrames = []
        scopes = []
        onMain { self?.onStackChanged?(); self?.onVariablesChanged?() }
    }

and the whole of `DAPClient.stop()`, in order: clear both readability handlers,
cancel the connection, cancel the listener, terminate the process. The handlers
go **first**, so from the moment `stop()` is entered nothing the adapter says is
read again.

Two things depend on output that arrives after `disconnect`:

- **`noteExitCode(inOutput:)`**, which exists because Delve never sends an
  `exited` event and reports the status as a sentence — "has exited with status
  N" — in the console stream. Its own comment says the status "usually arrives
  after the session is already over", and it publishes `.terminated` a second
  time so the toolbar can pick up the code. On a user-initiated stop that
  sentence is never read, so the toolbar shows a bare "Finished" where it has
  "Finished — exit code 0" to show.
- **The console**, which is the adapter's own words. Killed mid-sentence, it
  simply stops, and a log that stops looks exactly like one that is waiting.

Meanwhile `threads` — the goroutine list, `public private(set) var threads` — is
cleared by nothing anywhere in the file, and `onThreadsChanged` is fired only by
`refreshThreads`. Both the stop path and the adapter's own `terminated`/`exited`
handler empty `stackFrames` and `scopes` and leave the goroutines alone.

## Goals / Non-Goals

**Goals:**

- The panes describe the program that is there, which after a stop is none.
- The exit status is shown when the adapter is willing to say it.
- The console records that the session ended, whether or not the adapter says
  anything.
- The stop button always returns.

**Non-Goals:**

- Changing what Stop *does* to the program. `terminateDebuggee: true` is right
  and stays.
- Making Delve behave like a well-mannered adapter. It reports status in prose;
  the code already knows and parses it, and this only keeps the stream open long
  enough to hear it.
- A general session-lifecycle log. One line at the end, matching what the toolbar
  already says.

## Decisions

**Wait for the adapter's answer, with a deadline, and tear down afterwards.**
`disconnect` is a request and adapters answer it; that answer is the natural
moment to stop reading. The wait is bounded and short — an adapter that has not
answered in that time is one that is not going to, and gets what it gets today.

Against two others:

- *Do not wait; ask for the status another way.* There is no other way for Delve
  — that is why the sentence parser exists.
- *Wait for the `terminated` event instead.* Delve does not send one reliably,
  which the existing comment says in as many words. The `disconnect` response is
  the thing every adapter owes.

**Where the wait happens matters more than its length.** `DAPClient.stop()`
already carries a note that it is reached from the stop button and from menu
actions — the main thread — and that a half-second busy-wait there was being
recorded as idle time. Adding a second wait on that thread would make the
existing complaint worse. So the stop becomes asynchronous: the session goes to
`.terminated` at once so the toolbar and the panes update immediately, and the
adapter is drained and torn down behind it. The user's Stop is instant; the exit
code arrives a moment later, which is exactly the path `noteExitCode` was already
written for.

**The end-of-session line is the app's, not the adapter's.** Written to the
console when the session terminates however it terminated: finished, finished
with a code, or stopped before the adapter answered. The console already carries
"Building …" and Delve's banner, so a lifecycle line is in keeping — and it is
the only thing that distinguishes "this program ended" from "this pane is idle".
Its words match the toolbar's, because two different sentences for one fact is
how somebody comes to think they are two facts.

**`threads` is cleared where `stackFrames` is, in both places.** The two paths —
the user's stop and the adapter's `terminated`/`exited` — should not have
different ideas about what is left over. Fired through `onThreadsChanged`, or the
table keeps drawing what it last had.

**A stop that could not be completed is not a clean finish.** An adapter that
misses the deadline is killed, as now, and the console says so. That is the case
where "Finished" is a lie, and it is the one somebody needs to know about because
the process may still be there — which `RunningProcesses` is the place to check
and is out of scope here.

## Risks / Trade-offs

- **A wait on the stop path is a hang waiting to happen.** → It is off the
  button's thread entirely: the state changes at once and the draining happens
  behind it, so no gesture can block on an adapter.
- **The exit code arrives after the state does.** The toolbar therefore changes
  twice — "Finished", then "Finished — exit code 0". → That is what
  `noteExitCode` already does when a program exits on its own, so it is the
  established behaviour rather than a new flicker.
- **An adapter that answers `disconnect` and then says more.** → The deadline
  covers it; anything after teardown was never going to be read anyway.
- **Clearing threads removes something somebody may still be reading.** A stack
  after the program has gone is occasionally useful. → It is not a stack, it is a
  goroutine *list*, and it cannot be selected or expanded once the adapter is
  gone; leaving it is offering a control that does nothing.

## What the driven runs actually showed

Recorded because two of them contradicted what this document predicted.

**The stop path has no exit status to recover.** Predicted: keeping the stream
open would let Delve's "has exited with status N" through and the toolbar would
gain a code. Measured, a stop produces

    Detaching and terminating target process

and nothing else. The program did not exit — Delve killed it — so there is no
status, and `Finished` with no code is the true answer. What the premature
teardown was actually losing on this path is the adapter's last words.

**The status belongs to the other path, and it arrives late.** A program that
reaches its own end produces, in this order:

    total 6
    Process 97912 has exited with status 0

which is why `noteExitCode` publishes `.terminated` a second time. That worked
before and still works: `code=0` reaches the toolbar.

**Writing the console line on the `terminated` event was too early.** It produced

    total 6
    [Finished]                                ← ours
    Process 97912 has exited with status 0

— a console saying "Finished" beside a toolbar saying "Finished — exit code 0",
which is the exact failure this change set out to avoid, introduced by this
change. A toolbar re-renders; a console line is appended once and cannot be taken
back. So the adapter's own ending now waits for the `disconnect` reply too,
through the same drain the stop path uses, and the line comes last:

    total 6
    Process 7574 has exited with status 0
    Detaching
    [Finished — exit code 0]

**An asynchronous stop is wrong for a closing window, which this nearly
broke.** `DebugPane.shutdown()` calls `session.stop()`, and `shutdown` runs when
the *window* closes — so with the stop returning before the adapter is dead, the
pane, the callback and any chance of finishing the teardown go with it, leaving
the adapter running. `DAPClient.stopNow` spells out why that is not untidiness:
Foundation does not mark a pipe's descriptors close-on-exec, an adapter that
outlives its session holds open every pipe that existed when it started, and two
stray ones left by a test once cost twenty minutes of a suite that takes
fourteen seconds. So teardown keeps the old behaviour under its own name,
`stopImmediately`: ask, then kill, without waiting for an answer nobody is left
to read.

**Delve answers `disconnect` in 0.016 s.** Three runs: 0.015, 0.016, 0.017 on a
stop; 0.001 on a program that had already exited. The deadline is one second —
sixty times the slowest — which is the margin for a loaded machine rather than a
number that felt right.

**The goroutine list, before and after.** `threads=7 frames=3 scopes=1` at the
breakpoint; `threads=7 frames=0 scopes=0` after Stop, unfixed, with
`* [Go 1] main.main (Thread 27497960)` still listed — the reported screenshot,
reproduced. `threads=0 frames=0 scopes=0` after.

## What was ruled out

Written while doing it.

**Waiting for `terminated` instead of for the `disconnect` reply.** It is the
event that means what is wanted, and Delve does not reliably send it — which is
the same fact `noteExitCode` was written for, and the reason its comment says the
status "usually arrives after the session is already over". The `disconnect`
response is the thing every adapter owes, so that is what is waited for. Delve's
measured reply time is beside the deadline constant, and the driven run that
produced it is in the tasks.

**Waiting on the stop button's thread.** `DAPClient.stop` already carries a note
about a bounded half-second busy-wait on the main queue being recorded as idle
time. A second wait there would have made an existing complaint worse for the
sake of a gesture that must return.

**Moving `stopNow` off the main thread entirely**, which would have removed that
existing complaint rather than merely not adding to it. It touches the process,
three pipes, the connection and the listener with no lock over them, and this
change has no measurement of what races there. Left alone deliberately: the
comment says the wait is bounded and last on the list, and it still is.

**Reporting a clean finish when the adapter never answered.** The deadline path
kills the adapter exactly as before, but calling that "Finished" is the case where
the word is a lie — the process may still be there. It says it was stopped and
the adapter did not answer. Whether the process actually went is a question
`RunningProcesses` could answer and this does not ask.

**A general session-lifecycle log.** One line, matching the toolbar. A console
that narrates every transition is one nobody reads.

**Clearing `threads` only on the stop path**, which is where the report was. The
adapter's own ending leaves the same list behind, and two paths with different
ideas about what is left over is what produced this in the first place — so the
clearing is one function called from both.

## Open Questions

- **Should the last stack survive the session?** Asked because the argument for
  keeping the goroutine list would have been the same one, and it was made for
  neither. Answered here: no, and for a reason that is about the control rather
  than the data. A stack after the adapter is gone cannot be selected, expanded
  or navigated from — every row is a request to a process that is not there — so
  keeping it offers a list that does nothing, which is worse than an empty pane
  that says the session ended. If the last stack is wanted it wants *saving*,
  named as a thing that was, not left on screen looking live. That is a separate
  item and a real feature.
- Whether the frames should be kept *while* the console line is being read, so
  the two are visible together for a moment. Almost certainly over-thinking it.
- What the line says when the program was still running rather than stopped at a
  breakpoint — "stopped" and "finished" are different things and the toolbar
  currently says the same word for both.
- Whether `RunningProcesses` should be consulted when the deadline is missed, so
  the console can say whether the process actually went. That is a bigger claim
  than this change needs, and it is where a real answer would come from.
