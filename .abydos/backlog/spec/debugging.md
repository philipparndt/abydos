# Debugging

The first page written about the debugger, and it covers one thing: what a
session leaves behind when it ends. `run-configurations.md` says what a project
can run and mentions the debugger nowhere, so there was no page to add to. The
rest of debugging — breakpoints, stepping, watches, the variables tree — is still
undescribed, and stays that way until something touches it.

The adapter is spoken to over the Debug Adapter Protocol, and adapters differ in
what they volunteer. Delve is the one that shapes this page: it never sends an
`exited` event and reports the program's status as a sentence in the console
stream, which the code parses because that is where VS Code reads it from too.

## Requirement: A session that has ended leaves nothing of the program on screen

When a session ends, the panes stop describing a process that is not there: no
stack frames, no scopes, and **no goroutines**.

There are two ways a session ends — somebody presses Stop, and the adapter says
it is over — and they must leave the same thing behind. They did not. Both
emptied the frames and the scopes; the goroutine list was cleared by nothing
anywhere, so a Go service stopped at a breakpoint went on showing
`* [Go 1] main.main (Thread 27497960)` after the process had gone. Measured
before it was fixed: `frames=0 scopes=0 threads=7`.

Emptying a list is half of it. The table is told, or it goes on drawing what it
last had.

### Scenario: stopping at a breakpoint

- **Given** a Go service stopped at a breakpoint, with seven goroutines listed
- **When** Stop is pressed
- **Then** the goroutine list is empty, and so are the frames and the scopes

### Scenario: a program that ends on its own

- **When** the adapter reports the session terminated
- **Then** the same three are empty

## Requirement: Stopping reads the adapter's answer before killing it

Stopping sends `disconnect` and then reads what comes back, briefly, before
tearing the adapter down.

It used to send `disconnect` and immediately clear both readability handlers, so
the request just sent was never read and nothing said afterwards arrived.

What arrives in that window differs by how the session ended, and the difference
is measured rather than assumed. **Stopped**, Delve says `Detaching and
terminating target process` and reports no status — the program did not exit, it
was killed — so "Finished" with no code is the true answer. **Ended on its own**,
Delve reports the status as the sentence "has exited with status N", which is
parsed out of the console stream and can only be read while the stream is open.

The deadline is one second. Delve answers in 0.016 s, measured on this machine
across runs; the margin is for a loaded machine, where this suite has been seen
at load 65.

**Nothing waits on the thread the button is on.** The session goes to terminated
at once, so the panes and the toolbar answer immediately, and the adapter is
drained behind it. The exit code arriving a moment after the state is the path
that already existed for a program that ends on its own. `DAPClient.stop` carries
a note about a bounded busy-wait on the main queue being recorded as idle time,
and this must not add a second one.

An adapter that does not answer within the deadline is killed, as before.

### Scenario: stopping a program that was still running

- **Given** a program stopped under Delve at a breakpoint
- **When** Stop is pressed
- **Then** what the adapter says on its way out is shown rather than cut off
- **And** the console says it finished, with no code, because a terminated
  program reported none

### Scenario: the status arrives in prose

- **Given** a program under Delve that reaches its own end
- **When** it exits
- **Then** the status Delve reports in a sentence reaches the toolbar

### Scenario: an adapter that will not answer

- **When** the deadline passes with no reply
- **Then** the adapter is killed

## Requirement: The console says the session ended

One line on the console when a session ends, in the app's own words: that it
finished, the exit code where there is one, and — where the adapter never
answered — that it was stopped rather than finished.

Every other word in that console belongs to the adapter. "Building /Users/…" and
Delve's banner are the adapter speaking, so when it has nothing to say the log
simply stops, and a log that stops cannot be told from one that is waiting.

The words are the toolbar's — "Finished", "Finished — exit code 0", "Failed —
exit code N" — because two sentences for one fact is how somebody comes to
believe they are two facts.

Written once per session, whichever of the two paths ended it. Both can be
travelled for one session: a stopped program often produces the event as well.

### Scenario: a clean finish

- **When** a program ends with status 0
- **Then** the console says `Finished — exit code 0`, and the toolbar says the
  same

### Scenario: a program that was stopped rather than finished

- **When** Stop ends a program that had not reached its end
- **Then** the console says `Finished`, with no code invented for it

### Scenario: stopped before the adapter answered

- **When** the deadline passes and the adapter is killed
- **Then** the console says it was stopped and the adapter did not answer,
  rather than reporting a clean finish

### Scenario: both paths for one session

- **When** a stop is followed by the adapter's own `terminated`
- **Then** the console says so once
