## Context

Two kinds of pane are drawn by the same `TerminalView`:

    a shell          TerminalView(workingDirectory:command:startsProcess: true)
    a program's out  TerminalView(workingDirectory: nil, command: nil,
                                  startsProcess: false)

`startsProcess` is stored as `runsProcess`, and three things read it:

    override var acceptsFirstResponder: Bool { runsProcess }
    var showsOutputOnly: Bool { !runsProcess }
    guard !runsProcess, !pty.isRunning else { return }   // adopting a process

The first is the whole of the reported fault: a console refuses first responder,
so no key event reaches it and ⌃C is not ignored — it is never delivered.

**And underneath there is nothing.** A `TerminalPane(readOnly:)` holds a
`PseudoTerminal` object that is never launched: `pendingLaunch` is nil for
`startsProcess: false`, so no child is ever started. Four panes are built this
way — the devcontainer's *preparing* terminal, two streaming-log panes, and
`DebugPane.console` — and none of them owns a process.

A **Run** console is not one of them. `runCommand` builds
`TerminalPane(workingDirectory:command:)`, a real terminal with a pty running the
user's shell, so ⌃C there is encoded and written to the pty like any keystroke
and the line discipline does the rest. The fault was never in a Run console or a
shell tab.

So the reported case is the debugger's console, and the program in it is a JVM the
java-debug adapter launched. Its output reaches the pane as DAP `output` events.
Stopping it is a request to the adapter — which is what the Stop button already
makes.

## Goals / Non-Goals

**Goals:**

- ⌃C in a console stops the program, the way it does in any terminal.
- The output stays on screen and the tab stays open.
- A shell tab behaves exactly as it does now.

**Non-Goals:**

- Making a console interactive — arbitrary typing into a program's stdin.
- Changing what closing a tab does.
- Escalating to `SIGKILL` when a program ignores the interrupt.

## Decisions

**The console takes the keyboard, and that is the change.** Everything else
follows: once a key event arrives, carrying it is the part the terminal already
knows how to do. The alternative — a Stop item in a menu, or a button on the tab
— was considered and is not the same thing: somebody whose program is printing
reaches for ⌃C, not for a menu, and a control that does what ⌃C does while ⌃C
does nothing is a worse answer than the one key working.

**It is a request to the adapter, and it is described as one.** There is no
signal to choose between, because there is no local process — the design's
original open question, `SIGINT` to the group or `0x03` down the pty, was asked
about a pty that does not exist. ⌃C makes the same request the Stop button makes.

**And that difference is stated rather than hidden.** A program that traps
`SIGINT` to shut down cleanly will not see one, because none is sent: the adapter
terminates the debuggee. Somebody who presses ⌃C expecting their handler to run
would otherwise conclude their handler is broken.

**One key and not a keyboard.** Taking first responder means every key now
arrives somewhere that used to receive none, so what happens to the *others* has
to be decided rather than left. They are dropped: a console is not a shell, the
program behind it is usually not reading stdin, and delivering arbitrary
keystrokes to it is a feature nobody asked for with a failure mode — a program
that *is* reading stdin quietly receiving whatever was typed at a pane somebody
thought was read-only.

Ruled out: making the console fully interactive as part of this. It is a
defensible feature and it is a different one; doing it here would mean the change
that fixes ⌃C also decides what a run console's stdin is, and those deserve
separate arguments.

**The tab stays open and the scrollback stays**, which the Stop button already
gives — this adds the key, not a new kind of stop.

**Only the debugger's console, and not the other three read-only panes.** The
*preparing* terminal adopts a real shell later and has nothing to stop meanwhile;
the two log panes stream from something upstream whose stopping means something
different for each. Widening to them would mean deciding three separate questions
inside a change reported about one.

## What the building found

The change was proposed believing a console had a pty behind it and that ⌃C was
simply not being delivered to it. Half of that is right — the key is not
delivered, because `acceptsFirstResponder` is `runsProcess`. The other half is
wrong: there is no pty, no child process, and nothing a signal could reach. The
mechanism is a DAP request and the scope is one pane, not four.

## Risks / Trade-offs

- **First responder changes where the keyboard is.** A console that can take the
  keyboard may take it at a moment nothing expects — on a run starting, on a tab
  becoming active — and keys that used to reach the editor would stop. → The pane
  takes it on a click, as any view does, and what a run does with focus on start
  is left exactly as it is.

- **A shell tab must not change.** Everything here is behind `runsProcess` being
  false, which no shell has. → The regression to watch for is a shell that stops
  accepting keys, and it is worth a driven check rather than an assumption.

- **A console whose session has already ended.** ⌃C then has nothing to ask for.
  → It does nothing and says nothing, as a terminal at a dead prompt does.

- **It looks like an interrupt and is not one.** Somebody with a `SIGINT` handler
  will find it never runs. → Said in the words that describe it, and the reason
  this design refuses to call it an interrupt anywhere.

## Open Questions

- **Whether the debug console should take the keyboard on start or only on a
  click.** Taking it on start makes ⌃C work without aiming; it also moves the
  keyboard away from the editor every time somebody presses Debug, which is the
  more annoying of the two and the harder to notice as a cause.

- **Whether `terminate` or `disconnect` is the right request**, and whether it
  should differ for a session that *attached* — where terminating is stopping
  somebody's service and disconnecting is walking away from it. The Stop button
  has already answered this for itself and the answer should be the same one, not
  a second opinion.

- **Whether the two log panes want the same key**, once somebody has said what
  stopping a stream should mean. Not asked here.
