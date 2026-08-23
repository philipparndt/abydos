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

### Requirement: A stopped frame shows its variables beside the code that names them

While a session is stopped, the editor SHALL draw the value of a variable at the
end of each line that names it, in the file the selected frame belongs to.

The values SHALL be the ones the adapter has already returned for that frame —
its scopes and their variables — and **nothing further SHALL be asked of the
adapter to draw them**. No `evaluate`, and no request per line: in several
languages evaluating runs the debuggee's own code, and drawing a hint must not
be able to change the program being debugged.

A name SHALL match only as a whole token, so that `count` is not found inside
`counter` or `account`, and a name SHALL NOT match where it follows a dot: in
`self.count` and `shape.width` the name belongs to something else, and the local
of that name is a different thing.

Values SHALL be drawn only for lines at or above the line execution stopped at.
Below it a value is either left over from a previous pass or not yet assigned,
and it would be drawn in the same grey as one that is true.

Each hint SHALL be one line, truncated where the value is long, and SHALL be
drawn after the last character of the line so that no code moves. Where a line
names several variables in scope they SHALL appear in the order they occur on
the line.

Nothing SHALL be drawn, and nothing computed, while no session is stopped.

#### Scenario: stopped at a breakpoint

- **GIVEN** a session stopped in a file that is open
- **WHEN** the editor draws that file
- **THEN** each line at or above the stopped line that names a variable of the
  selected frame shows that variable's value at its end

#### Scenario: another file, and another frame

- **GIVEN** the same stop, with a second file open that the frame is not in
- **THEN** that file shows no values
- **AND** selecting a different frame in the stack moves the values to that
  frame's file and its own variables

#### Scenario: a name that is part of a longer one

- **GIVEN** a frame with a variable named `count`
- **WHEN** a line reads `accountTotal = counter + 1`
- **THEN** nothing is drawn for it

#### Scenario: a name that belongs to something else

- **GIVEN** the same frame
- **WHEN** a line reads `self.count`
- **THEN** nothing is drawn for it, the local of that name not being that field

#### Scenario: nothing is running

- **GIVEN** a session that has resumed, ended, or never started
- **THEN** no values are drawn, and none are worked out

#### Scenario: a value too large to sit on a line

- **GIVEN** a variable whose value is a page of text, or has newlines in it
- **THEN** what is drawn is a single truncated line
- **AND** the whole value is still readable in the variables tree

### Requirement: A value beside the code can be opened up

A value drawn beside the code SHALL be openable where the variable it stands for
has children, into a window showing that variable with its fields under it.

`stage = "local"` is a whole answer at the end of a line. `mux = *net/http.ServeMux
{mu: sync.RWMutex {w:…` is a type name and forty characters cut mid-word, and a
struct does not fit at the end of a line at any budget — so what is needed is not
more characters but somewhere with room.

**Whether there is anything to open SHALL be the adapter's answer**, which is
`variablesReference > 0`, and not a guess made from the value's text. A hint that
can be opened SHALL show that it can before it is pressed, and one that cannot
SHALL do nothing when it is.

**Children SHALL be fetched on the gesture, never on a repaint.** A request per
hint per draw is what makes a stopped editor unusable; opening one is one
request, made because somebody asked for it.

The window SHALL expand and lazily load exactly as the variables tree in the
panel does, from one implementation rather than two, and SHALL be dismissed by
Escape, by a click outside it, and by execution resuming — a tree of values from
a program that is running again is worse than no tree.

**It SHALL be walkable with the keyboard and resizable.** A tree is read by
walking it: ↑ and ↓ move, → opens a row and ← closes it, which an outline view
answers by itself once it has the keyboard — so the window SHALL take the
keyboard when it opens, and expanding a row SHALL NOT lose what was selected.
Rebuilding the rows under a node drops a selection the view can no longer place,
so what is selected SHALL be remembered by the item rather than by the row. And a
struct is why the window exists, so its size SHALL be the reader's: it carries a
title bar to drag, edges to pull, and a close button.

The same SHALL be true of the panel's own tree, which knew the keys and never
received them: **clicking it SHALL give it the keyboard, and expanding a row
there SHALL NOT lose what was selected either.** Reported twice from use, and the
second time in the panel: the panel rebuilds its whole tree from the session's
answer, so its rows are new objects and remembering the item is not enough — a
row SHALL be remembered by what it names, a scope by its index, a variable by its
scope and path, a watch by its expression.

And a selected row SHALL be drawn in the theme's colour in both, **from one row
view rather than two**: the window opened beside the code drew the system's blue
while the panel below it drew the theme's orange, because the class that drew the
theme was private to the panel.

Nothing about the line SHALL change: the same text, in the same place, truncated
the same way.

#### Scenario: a struct at the end of a line

- **GIVEN** a session stopped where `mux` is a `*net/http.ServeMux`
- **WHEN** the value drawn beside that line is clicked
- **THEN** a window opens on `mux`, showing its fields, each expandable

#### Scenario: something with nothing in it

- **GIVEN** the same stop, and `stage = "local"` on another line
- **WHEN** that value is clicked
- **THEN** nothing opens, and the click does what a click in the editor does

#### Scenario: it says which is which

- **GIVEN** both values on screen
- **THEN** the one that can be opened is distinguishable from the one that
  cannot, before either is clicked

#### Scenario: nothing is asked for until it is asked for

- **GIVEN** a file full of lines naming containers, scrolled through while
  stopped
- **THEN** no `variables` request is made for any of them
- **AND** one is made when a hint is opened

#### Scenario: walking it with the keyboard

- **GIVEN** a value opened up
- **WHEN** ↓ is pressed and then →
- **THEN** the selection moves to the field and the field opens
- **AND** what is selected is still selected once its children have arrived

#### Scenario: walking the panel's tree

- **GIVEN** the panel's variables tree, clicked, with a container selected
- **WHEN** → is pressed and the adapter answers with its children
- **THEN** the container is still selected, and the tree has grown by its
  children

#### Scenario: one colour for a selected row

- **GIVEN** a value opened beside the code and the panel's tree below it
- **THEN** a selected row is drawn the same colour in both, and it is the
  theme's rather than the system's

#### Scenario: clicking the panel's tree

- **GIVEN** a stopped session with the variables tree showing in the panel
- **WHEN** a row is clicked
- **THEN** the tree has the keyboard, and the arrows walk it

#### Scenario: the program is let go

- **GIVEN** a value opened up
- **WHEN** execution resumes
- **THEN** the window goes, with the values beside the code

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

### Requirement: A debug session can be stopped from its console

⌃C in the debugger's console SHALL stop the session, making the same request the
Stop button makes.

**It is not an interrupt, and SHALL NOT be described as one.** The console is a
`TerminalPane(readOnly:)` whose `PseudoTerminal` is never launched: there is no
local process and nothing a signal could reach. The program is one the adapter
started — for Java, a JVM — and its output arrives as DAP `output` events. So
stopping it is a request to the adapter, and a program that traps `SIGINT` will
not see one, because none is sent. Saying that plainly is the difference between
somebody understanding their handler was skipped and concluding it is broken.

**The console SHALL take the keyboard, which today it does not.**
`acceptsFirstResponder` is `runsProcess`, false for a pane that shows output, so
⌃C is not ignored — it is never delivered.

**Taking one key SHALL NOT make the console interactive.** The program behind it
is usually not reading stdin, and a pane somebody believes is read-only quietly
delivering what they typed is a worse fault than the one being fixed. Other keys
are dropped.

**The output SHALL stay and the tab SHALL stay open**, as they do when the Stop
button is used. This adds the key, not a new kind of stop.

#### Scenario: a program printing under the debugger

- **GIVEN** a debug session whose program is printing into the console
- **WHEN** ⌃C is pressed with that console focused
- **THEN** the session stops, as though Stop had been pressed
- **AND** the output is still on screen, and the tab is still open

#### Scenario: a session that has already ended

- **GIVEN** a console whose session has ended
- **WHEN** ⌃C is pressed
- **THEN** nothing happens, and nothing is said about it

#### Scenario: typing into a debugger's console

- **GIVEN** a console showing a program's output
- **WHEN** ordinary characters are typed
- **THEN** they do not reach the program

#### Scenario: a shell or a Run console is unchanged

- **GIVEN** a terminal tab, or a console from Run — both of which have a pty
  running a shell
- **WHEN** ⌃C is pressed
- **THEN** it travels the pty as it always did, and nothing here changed it
