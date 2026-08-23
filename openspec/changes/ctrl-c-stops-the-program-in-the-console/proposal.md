## Why

**A program running in the console cannot be stopped with ⌃C, and the reason is
that the console cannot take a keystroke at all.**

Reported while a Java program was being debugged: it prints a line a second and
there is no way to make it stop from the console it is printing into. Every
terminal anybody has used since 1979 stops a program with ⌃C, and the pane it is
printing into looks exactly like a terminal — because it *is* one, drawn by the
same `TerminalView` as the shell in the next tab.

The difference is one flag. A console for a program's output is made with
`TerminalView(workingDirectory: nil, command: nil, startsProcess: false)`, and
`startsProcess` becomes `runsProcess`, and:

    override var acceptsFirstResponder: Bool { runsProcess }

So the view refuses the keyboard. Not "reads ⌃C and does nothing with it" —
never receives it. There is no path from a keystroke to the program, and the
only thing that stops one is closing its tab, which goes through
`terminateProcess` → `PseudoTerminal.terminate` → `SIGHUP` to the process group.

**That is a stop with no gentler option in front of it.** Closing the tab kills
the program *and* takes away the output that says what it did before it died,
which for a service is the part somebody wanted to read. ⌃C exists precisely so
a program can be asked to stop while its scrollback stays.

**And there is nothing behind it to signal.** This was written believing the
console had a real pty like any other pane; it has not. `TerminalPane(readOnly:)`
never launches its `PseudoTerminal` at all — the JVM was started by the java-debug
adapter, and its output arrives as DAP `output` events and is written into the
emulator. So ⌃C here cannot be a signal to anything: there is no local process.

**Which narrows the change and changes its mechanism.** A *Run* console is a real
terminal — `runCommand` builds one with a pty running the user's shell — so ⌃C
already works there, and in every shell tab. What does not work is the
**debugger's** console, and stopping a program there means asking the adapter to
terminate the debuggee: the thing the Stop button already does, on the key
everybody reaches for.

No originating backlog item: the backlog was dropped on 2026-08-19, and this was
reported on 2026-08-23.

## What Changes

- **⌃C in the debugger's console stops the debug session**, through the same
  request the Stop button makes. It is not a signal and SHALL NOT be described as
  one: a program that traps `SIGINT` will not see one, because none is sent.
- **The console takes the keyboard**, which is what it does not do today. This is
  the whole mechanism, and it is why the change is not one line.
- **The scrollback stays.** A stopped program leaves its output where it is, and
  the tab stays open — which is the difference between this and closing the tab,
  and the reason somebody wants it.
- **Nothing changes for a shell or a Run console.** Both have a pty and both
  already take ⌃C; the fault was never there.
- **Not proposed: typing into a program's console.** Taking the keyboard for one
  key is not the same as making the pane interactive, and a console that echoed
  arbitrary input into a program's stdin is a different feature with its own
  questions — not least what it means for a program that is not reading stdin.
- **Not proposed: changing what closing the tab does.** `SIGHUP` to the process
  group is right for "this tab is going away", and stays.

## Capabilities

### Modified Capabilities

- `debug-sessions`: a second way to stop a session, and what it is. *Stopping
  waits for the adapter's answer* already describes the stop itself; this adds the
  key that asks for it and says plainly that it is a request to the adapter rather
  than an interrupt to a process.

## Impact

- `Sources/AbydosApp/Terminal/TerminalView.swift` — `acceptsFirstResponder` is
  keyed on `runsProcess`, which is why no key arrives, and the one key that is
  carried out of such a view.
- `Sources/AbydosApp/Panel/DebugPane.swift` — the console that gets the key, and
  the stop it asks for.
- `Sources/AbydosKit/Terminal/PseudoTerminal.swift` — untouched. Nothing is
  signalled, because there is nothing running locally to signal.
- No new dependency, and nothing new on anybody's machine.
