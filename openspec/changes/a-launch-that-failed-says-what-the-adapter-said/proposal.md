## Why

**A debug launch that the adapter refused in milliseconds is reported
twenty-five seconds later, as a guess.** Reported today, on
`~/dev/smarthome/projects/mqtt-lamarzocco`:

    The debugger did not start
    The debugger stopped without starting the program. The last thing it said was:
    Building /Users/philipparndt/dev/smarthome/projects/mqtt-lamarzocco/app

Driven against the same adapter, `dlv dap` answered all of this **at once**:

    output  (stdout)  Building /…/mqtt-lamarzocco/app
    output  (stderr)  Build Error: go build -o /… -gcflags all=-N -l /…/app
                      go: cannot find main module…
    launch  response  success=false
                      message="Failed to launch: Build error: Check the debug
                               console for details."

Three things are wrong with what the app did with that:

- **The response was thrown away.** `DebugSession` sends `launch` and never reads
  the answer, so a refusal that arrives in milliseconds is not noticed at all.
- **The twenty-five second watchdog is what reported it**, having been written for
  a launch that produced *no* event — which is not this. `LaunchStall`'s own
  comment says the adapter usually says why and that saying what it said beats a
  guess; here the adapter said why, in a `message` field, and the guess was shown
  instead.
- **The sentence shown was the wrong line.** `Building …` is the adapter clearing
  its throat. The explanation is the line after it and the `message` on the
  response, and neither reached the dialog.

For twenty-five seconds the window says nothing while the answer is already in.

No originating backlog item: the backlog was dropped on 2026-08-19 and this was
reported on 2026-08-21.

## What Changes

- **The `launch` response is read.** A response with `success: false` ends the
  launch there and then, with the adapter's own `message`.
- **The dialog says what the adapter said**, in this order of preference: the
  response's `message`, then what it printed on the way — and it names the
  console, which holds the whole of the build error, when the adapter says to
  look there.
- **The watchdog goes back to being about silence.** It stays exactly as it is
  for a launch that produces nothing at all — the developer-tools authorization
  case it was written for — and stops being the thing that reports refusals.
- **The same for `attach`**, which is sent the same way and whose refusal is
  dropped the same way.
- **Not proposed: shortening the watchdog.** Twenty-five seconds is right for the
  case it is for; a build that takes thirty is not a fault.
- **Not proposed: parsing the build error.** Whatever the compiler said is the
  clearest thing available and belongs in the console, unedited.

## Capabilities

### Modified Capabilities

- `debug-sessions`: it says a stopped session says so and what a launch that
  stalls reports. A launch the adapter *refused* is a different event with a
  different answer, and the capability does not tell them apart.

## Impact

- `Sources/AbydosKit/Debug/DebugSession.swift` — the `launch` and `attach` sends,
  and the watchdog that currently reports for them.
- `Sources/AbydosKit/Debug/DAPClient.swift` — responses are already matched to
  requests for everything else; this is one more caller reading one.
- `Sources/AbydosKit/Debug/LaunchStall.swift` — gains the refused case beside the
  silent one, so both sentences stay in one place readable without a window.
- Not in scope, found on the way and worth their own items: **dlv 1.26.2 refuses
  Go 1.27.0** on this machine ("maximum supported version 1.26"), which the app
  will report properly once this change lands; and **a Go module that is not at
  the project root** — `mqtt-lamarzocco` keeps its `go.mod` in `app/` — needs the
  launch's working directory to be the module's, which is the likeliest reason
  this particular build failed at all.
