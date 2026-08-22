## Context

`DebugSession.launch` ends with two lines:

    client.send("launch", arguments: …)
    startLaunchWatchdog()

`send` is fire-and-forget. Every other DAP request this app makes goes through
the awaited path and reads its answer; `launch` and `attach` are the two that do
not, and they are the two whose failure matters most.

The watchdog was written for a launch that produces *nothing*: macOS holds a
debuggee until developer-tools authorization is answered, and the app used to
report that cause whatever had happened. `LaunchStall` fixed the *wording* — it
keeps the last twelve lines the adapter printed and shows them instead of
guessing — and left the shape alone: the report still happens twenty-five seconds
later, and only from output, never from the answer to the request.

Measured against `dlv dap` on the reported project: `Building …`, then
`Build Error: …` with the compiler's own sentence, then
`launch success=false message="Failed to launch: Build error: Check the debug
console for details."` — all inside a second. The dialog appeared twenty-five
seconds later carrying the first of those three.

## Goals / Non-Goals

**Goals:**

- A refused launch is reported when it is refused.
- What is shown is what the adapter said about it.
- The silent case keeps the message and the timing it has.

**Non-Goals:**

- Interpreting a build error, or a compiler's output.
- Changing what the console shows. It already has the whole of it.
- Fixing the two things found on the way — the delve version gate and the module
  root — which are their own items.

## Decisions

**Read the response; do not race the watchdog.** The response is the fact: the
adapter, asked to launch, said no and said why. Anything else is inference from
output that happens to have arrived by a deadline.

**The `message` first, then the output.** `message` is one sentence written for a
person — "Failed to launch: Build error: Check the debug console for details." —
and the output is the detail. So the dialog leads with the message and includes
what was printed, which is where `go: cannot find main module` actually is. Where
there is no `message`, the output alone is what there is, which is today's
behaviour.

**And name the console when the adapter points at it.** `showUser: false` and
"Check the debug console for details" are the adapter telling the client where
the rest is. A dialog that repeats the sentence and does not say the console is
already open one pane away is a dialog that has to be dismissed to be acted on.

**The watchdog stays, unchanged, for silence.** Twenty-five seconds is right for
the authorization case, where nothing at all comes back — and a build that takes
thirty seconds is not a fault, so shortening it would invent failures. What
changes is that a refusal no longer waits for it.

**`attach` is the same two lines and gets the same treatment.** A refused attach
is exactly as silent today, and a debugger attached to nothing is worse than one
that says why it did not.

**Ruled out: reporting on the `terminated` event instead.** Delve does not send
`exited`, and `terminated` after a failed launch is indistinguishable from a
program that ran and stopped. The response says which of the two happened.

**Ruled out: matching on the text of the message.** "Build error", "could not
launch", "exec format error" — all wordings, all adapters' own. The `success`
flag is the fact and the `message` is for showing, not for matching. The same
rule `DiagnosticWeight` states about `No such module`.

**Ruled out: shortening the watchdog to make refusals feel faster.** It would
make slow builds look like failures, which is the fault this change is fixing in
reverse.

## Risks / Trade-offs

- **An adapter that answers `success: true` and then fails** is not covered by
  this, and the watchdog still is. → Both paths stay.
- **Two reports for one failure** — the response and then the watchdog. → The
  watchdog is cancelled by the report, the way it already is by a `stopped`
  event.
- **A `message` that is useless** ("Failed to launch") without the output. → Both
  are shown, which is why the output is kept rather than replaced.

## Open Questions

- **Whether a refused launch should raise the console rather than a dialog.** The
  detail is there, the dialog quotes a summary of it, and two places saying one
  thing is the arrangement this project usually collapses. Left open because
  raising a pane on a failure is a bigger decision than a sentence.
- **What `attach` should say when the target is gone**, which is a different
  sentence from a build that failed and may deserve its own.
