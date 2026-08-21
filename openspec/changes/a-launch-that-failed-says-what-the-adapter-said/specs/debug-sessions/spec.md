## ADDED Requirements

### Requirement: A launch the adapter refused is reported when it is refused

A launch the adapter refuses SHALL be reported at once, from the adapter's own
answer, rather than by the watchdog that waits for silence.

Measured against `dlv dap` on a project whose build fails, everything the adapter
had to say arrived inside one second:

    output  (stdout)  Building /…/mqtt-lamarzocco/app
    output  (stderr)  Build Error: … go: cannot find main module…
    launch  response  success=false, message="Failed to launch: Build error:
                      Check the debug console for details."

The window said nothing for twenty-five seconds and then showed `Building …` —
the adapter clearing its throat — under a sentence about the debugger stopping
without starting the program. **The response was never read**: `launch` is sent
and its answer dropped, so a refusal is invisible until the watchdog gives up.

The `launch` request's response SHALL be read, and a response whose `success` is
false SHALL end the launch there, with what the adapter said about it. **The same
SHALL hold for `attach`**, which is sent the same way and refused as silently.

What is shown SHALL prefer the response's `message` — one sentence, written for a
person — and SHALL also carry what the adapter printed, which is where the
compiler's own words are. Where the adapter says the detail is in the console,
the report SHALL say so, because a dialog that has to be dismissed before its
advice can be followed is a dialog in the way.

**The success flag is the fact and the message is for showing.** The report SHALL
NOT be decided by matching the text of a message: "Build error", "could not
launch" and "exec format error" are wordings, and one adapter's wording at that.

#### Scenario: a build that fails

- **GIVEN** a Go project whose build fails
- **WHEN** it is debugged
- **THEN** the failure is reported as soon as the adapter refuses, not after the
  watchdog's wait
- **AND** what is shown includes the adapter's own message and what it printed

#### Scenario: the console holds the detail

- **GIVEN** an adapter whose message says to check the console
- **WHEN** the launch is refused
- **THEN** the report says the console has the rest

#### Scenario: an attach that is refused

- **GIVEN** an attach the adapter will not accept
- **WHEN** it is asked for
- **THEN** it is reported at once, with the adapter's own message

#### Scenario: a launch that says nothing at all

- **GIVEN** an adapter that answers nothing and starts nothing — a debuggee held
  for developer-tools authorization
- **WHEN** the wait is over
- **THEN** the watchdog reports it exactly as it does today, with the same
  sentence and the same timing

#### Scenario: a slow build is not a failure

- **GIVEN** a build that takes longer than the watchdog's wait and then succeeds
- **THEN** nothing is reported as a failure
