# 440. `abydos <file>` in the terminal opens it in the editor beside it

Typing `abydos ~/my-file.md` in one of this app's own terminals should open that
file in the editor of *that window*, put the keyboard in it, and get the terminal
out of the way if it is covering the editor. Three things, and the third is the
one that makes it a gesture rather than a background event: opening a file into a
pane nobody can see is the same as not opening it.

## Why the command as it stands cannot do it

`Scripts/abydos` ends with:

    exec open -a "$app" "$@"

That is right for what it was for — standing in a directory anywhere on the
machine and wanting it open — and it is the wrong shape for this. `open -a` goes
through LaunchServices, and what arrives at the app is "a file was opened", with
no way to know **which window asked**, no way to know it came from a terminal at
all, and so no reason to move the keyboard or restore a panel. It cannot even
tell running-inside-Abydos from running inside Ghostty, which is exactly the
distinction the behaviour turns on.

## The mechanism is already here, twice

**Through the pty, as an escape sequence.** The pane's own file descriptor is the
one channel that identifies the window without inventing anything: a socket, a
port, a lock file in `~/Library` — none of that is needed, because the terminal
this is typed into is already connected to the window that should answer.

- `TerminalEmulator` already parses OSC (`consumeOSC`/`finishOSC`) and already
  acts on OSC 52 by putting something on the clipboard on a program's say-so.
  This is the same shape with a different verb.
- `abydos-icat` is the worked example of a shipped command talking to this app
  from inside its own pane, and it is on the PATH of every shell the app starts
  without an install step — `PseudoTerminal.mergedEnvironment` appends the
  bundled directory.

**Take `abydos-icat`'s hard-won lessons rather than rediscovering them.** It
wraps its escapes for tmux (`\033Ptmux;…`) because tmux eats a sequence it does
not recognise unless passthrough is asked for explicitly, and it already knows
how to tell whether passthrough is on and to say so instead of failing silently.
A file that does not open and says nothing is the worst possible outcome here.

## The parts

**Absolute before it is sent.** The path is relative to the *shell's* working
directory, and the app's is somewhere else entirely. The script resolves it, and
resolves `~`, before the sequence goes anywhere.

**The terminal gets out of the way.** `terminalAtStartup = "full"` maximises the
panel, and there is a maximise toggle on it (`onToggleMaximize`,
`maximizeTerminalWhenLaidOut`). If the terminal is covering the editor when a
file arrives, it has to come back to a split. Worth deciding rather than
assuming: whether it returns to the height it had before it was maximised, and
whether it stays down afterwards or goes back up when the editor loses focus. The
first is almost certainly right; the second is a real choice.

**The keyboard moves.** That is the "put the cursor in there" half. Without it
the file is open behind a terminal that still has the keys, and the next thing
typed goes to the shell.

**Outside this app, nothing changes.** In Ghostty, Terminal.app or over ssh the
escape means nothing and the command must still do what it does today —
`open -a`, which is the right answer there. `abydos-icat` detects its host with
`TERM_PROGRAM`, and the same test serves here.

**`abydos` with no arguments still means "here".** It opens the directory as a
project, and that must not change.

## Worth deciding

- **What happens when nothing answers.** The sequence is written and the shell
  moves on; if the terminal was not this app's, or tmux swallowed it, the file
  never opens. Either the script waits briefly for an acknowledgement and falls
  back to `open -a`, or it does not and says what it assumed. `abydos-icat`
  already has the machinery for the first and it is not free — a query, a reply,
  and a timeout on a `/dev/tty` read.
- **A line number.** `abydos file.md:12` is the obvious neighbour and every
  editor's CLI has it; `+12` is the other spelling. Not in the sentence that was
  asked for, so it is written here rather than assumed into the work.
- **Several files**, which the command already accepts and which should probably
  open several tabs with the keyboard in the last.
- **A file outside the project.** It has to open somewhere; whether that is the
  current window as a loose file or a refusal is the same question the navigator
  answers for a file dropped from elsewhere.
