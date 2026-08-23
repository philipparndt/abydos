## ADDED Requirements

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
