# debug-sessions Specification

## Purpose
TBD - created by archiving change stopping-a-debug-session-says-so. Update Purpose after archive.
## Requirements
### Requirement: A session that has ended leaves nothing of the program on screen

The panes SHALL describe the program that is there, and after a session ends
there is none. The stack frames, the variable scopes **and the goroutine list**
are cleared, and each of the tables showing them is told.

The goroutine list was not. `stackFrames` and `scopes` were emptied on both paths
that end a session — the user's stop and the adapter's own `terminated` or
`exited` — and `threads` was cleared by nothing anywhere, nor was
`onThreadsChanged` fired, so `* [Go 1] main.main (Thread 27093656)` stayed on
screen for a process that had gone. Two paths to one place must not have
different ideas about what is left over.

#### Scenario: stopping at a breakpoint and pressing Stop

- **GIVEN** a Go service stopped at a breakpoint, with its goroutines listed
- **WHEN** Stop is pressed
- **THEN** the goroutine list is empty, along with the stack and the variables

#### Scenario: the program exits on its own

- **WHEN** the adapter reports the program terminated or exited
- **THEN** the same three are cleared, by the same rule

### Requirement: The console says the session ended

The console SHALL record the end of a session in the app's own words, whether or
not the adapter volunteers anything: that it finished, and the exit code where
there is one.

Every word in that console today is the adapter speaking — Delve's "Building
<path>" and its banner. When the adapter has nothing to say, or is killed before
it can, the console simply stops, and **a log that stops cannot be told from one
that is waiting**. The words SHALL match the toolbar's, because two sentences for
one fact is how somebody comes to believe they are two facts.

#### Scenario: a session stopped by the user

- **WHEN** Stop is pressed
- **THEN** the console says the session finished, rather than ending mid-stream

#### Scenario: a session that ended with a code

- **WHEN** the program exited with a status the adapter reported
- **THEN** the console names that code, and the toolbar shows the same one

### Requirement: Stopping waits for the adapter's answer, briefly, off the button's thread

Stopping SHALL send `disconnect` and read what the adapter says in reply, up to a
deadline, before tearing the connection down. Today the readability handlers are
cleared *first*, so from the moment Stop is pressed nothing the adapter says is
read again.

Two things arrive in that window, and they are not the same thing on the two
paths a session can end by.

**On a stop, it is the adapter's last words.** Driven against Delve, a stop
produces `Detaching and terminating target process` and **no status at all** —
the program did not exit, it was killed — so there is no code to recover here and
"Finished" without one is the true answer.

**On a program that ended by itself, it is the status.** Delve never sends an
`exited` event and reports it as the sentence "has exited with status N";
`noteExitCode(inOutput:)` exists to parse it out of the console stream and can
only work while the stream is still read. Moving the teardown must not break the
path that already worked.

The deadline SHALL be long enough for the reply and short enough not to hold a
session open. Delve answers in 0.016 s, measured; one second is the deadline, and
what it was measured against SHALL be recorded where it is chosen.

**The wait SHALL NOT be on the thread the Stop button is on.** The session goes
to terminated at once, so the panes and the toolbar answer immediately, and the
draining happens behind it; the exit code arrives a moment later, which is the
path that already exists for a program that exits on its own. `DAPClient.stop()`
already records that a bounded busy-wait there was being logged as idle time, and
this must not add a second one.

An adapter that misses the deadline SHALL be killed as it is now, and the console
SHALL say that is what happened rather than reporting a clean finish.

#### Scenario: Delve, stopped by the user

- **GIVEN** a Go session stopped at a breakpoint
- **WHEN** Stop is pressed
- **THEN** the panes clear at once
- **AND** what the adapter says on its way out is shown rather than cut off
- **AND** the console says the session finished, with no exit code, because a
  program that was terminated did not report one

#### Scenario: a program that ended on its own

- **GIVEN** a program run under Delve that reaches its end
- **WHEN** it exits
- **THEN** the status in Delve's parting sentence reaches the toolbar and the
  console, as it did before the teardown moved

#### Scenario: an adapter that will not answer

- **WHEN** the deadline passes with no reply
- **THEN** the adapter is killed, and the console says the session was stopped
  without the adapter answering

#### Scenario: the button returns

- **WHEN** Stop is pressed
- **THEN** it returns immediately, whatever the adapter does next

