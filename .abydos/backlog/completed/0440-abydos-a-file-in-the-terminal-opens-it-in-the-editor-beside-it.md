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

---

## What was built

### The wire

`Sources/AbydosKit/Terminal/TerminalOpenRequest.swift` is the whole of what the
two sides agree on, and `Scripts/abydos` is the other end of all three constants
in it:

    ESC ] 440 ; ?                       ST     is anybody there?
    ESC ] 440 ; abydos                  ST     the answer, from this app
    ESC ] 440 ; open ; <base64 path>    ST     open this
    ESC ] 440 ; open ; <base64> ; 12    ST     …and put the cursor on line 12

The path travels base64 because a path is arbitrary bytes: a semicolon in a file
name would end the field and a newline or an ESC would end the sequence. OSC 52
carries its payload the same way for the same reason. 440 is the number of this
entry; nothing standard claims it, and neither xterm, kitty, iTerm2 nor tmux uses
it — but it is a private extension, and a program emitting it elsewhere for some
other purpose would be read here as asking for a file. That is the same bet OSC
52 makes about the clipboard, taken knowingly.

`TerminalEmulator` answers the question and hands the request on;
`TerminalView` → `BottomPanel` → `MainWindowController` carries it to the window
the pane belongs to, which is the fact `open -a` could never supply. A pane in a
torn-off terminal window has no editor of its own, so its request goes to the
frontmost project window instead — still better than an escape reaching nobody.

The reading is deliberately narrow. A relative path is refused rather than
resolved, because the app's working directory is not the shell's and resolving
here would resolve against a directory nobody chose.

### The command

`Scripts/abydos` decides where a file should open as a function of five answers —
is there a terminal, what `TERM_PROGRAM` says, is tmux in the way, is tmux
passing escapes through, did the terminal answer — and nothing else. That is
`abydos-icat`'s shape rather than a new one: the cases are the part that sends
somebody to fix the wrong thing, so `--explain-open` hands the decision its five
answers and prints what it chose, and the tests put every combination of them
through the real script rather than a copy of it. Every decision has a sentence,
so a case added without one is a test failure rather than a silence.

Inside tmux `TERM_PROGRAM` is the word "tmux" and says nothing about the terminal
behind it, so it is not consulted there. Outside tmux it is the whole answer for
every terminal that is not this one, which is what keeps `abydos notes.md` in
Ghostty from waiting three tenths of a second for a reply that is never coming.

The path is made absolute before it goes anywhere, and the line number comes off
whichever way the file is about to open — `open -a main.go:214` names a file that
does not exist, and LaunchServices is right to say so. Arguments are rotated
rather than collected into a string, so a path with a space or a newline in it
survives. And the terminal is handed back exactly as it was found: asking a
question means turning off echo and line editing, and a command that leaves a
terminal like that is a worse bug than any it could be fixing.

`abydos` with no arguments still means here, and a directory is still a project —
LaunchServices' business however it was typed, so the terminal is not even asked.

### tmux has to be told to carry it

This is the part that was not in the entry, and without it the feature would have
worked on the machine it was written on and nowhere else.

When "start tmux in the terminal" is on, every pane this app opens is a tmux
pane — and tmux drops an escape it does not recognise unless the program wraps it
in tmux's own passthrough *and* the session is willing to carry it.
`allow-passthrough` is off unless somebody has turned it on. The author of this
change had `set -g allow-passthrough on` in their own `~/.tmux.conf`, so every
run looked right; for anybody else `abydos notes.md` would have printed a
sentence about tmux and opened the file in a window of its own, for ever.

So `TmuxMirror.attachArguments` now asks for it as the session is attached, in
the same breath as the attach:

    tmux new -A -s <project> ';' set-option -q -t <project> allow-passthrough on

A session option, exactly as the status bar above it is done: nothing is written
to anybody's `.tmux.conf`, and no session this app did not bring up is touched. A
session somebody made themselves and switched this terminal to keeps whatever
they set, which is theirs to decide. It is also less of a new permission than it
sounds — a program in a pane without tmux in it can write any escape it likes to
this terminal already, and tmux is the only thing that was ever standing between
the two. `-q` because tmux learned the option in 3.3, and on anything older the
right outcome is the behaviour there has always been rather than an error printed
into somebody's shell.

`abydos-icat` gets the same thing for free, having needed it just as much.

### Three bugs found by looking

None of these were the feature; all three were in its way.

**A pane is not inside tmux because the app was launched from a shell that was.**
`mergedEnvironment` passed the inherited `TMUX` straight through, so `make run`
from a shell inside tmux handed every pane a variable naming a session none of
them was in. `abydos <file>` believed it, wrapped its question in a passthrough
nothing was there to unwrap, heard no answer, and quietly opened the file through
LaunchServices — every part behaving correctly given what it had been told. It is
the same lie `TERM_PROGRAM` tells and is now removed the same way. Removed rather
than blanked: a pane that goes on to run tmux gets its own from tmux, which is
the only thing entitled to say so.

**A deferred reveal landed on the wrong tab.** `EditorViewController.open(fileURL:
atLine:)` scrolled `activeTab` on the next turn of the run loop rather than the
tab it had just opened. `abydos deep.txt:150 main.go` opens both in one turn, so
line 150 was revealed on `main.go` — a two-line file scrolled to a line it does
not have — while the file that asked for it sat at the top.

**The position indicator kept the previous tab's line.** It is one control shared
by a whole group, and `activate` refreshed the language but never the caret, so
bringing a tab forward left the last tab's line beside the new tab's language.
Easiest to see as "150:1 Go" next to a two-line file, but any click between two
tabs did the same.

## The four that were worth deciding

**What happens when nothing answers.** It waits, briefly, and falls back. The
terminal is asked first and the file is only sent to a terminal that has answered
— nothing here ever writes an escape and hopes. The deadline is `stty min 0 time
3`, three tenths of a second, an age for a program on the other end of the same
machine and long enough that a window under load still gets its word in; a single
`dd bs=64 count=1` returns the instant the first byte lands, so the common case
costs nothing rather than always costing the deadline. The cost the entry
predicted is real and is paid only where it buys something: a terminal that has
already named itself as somebody else's is never asked at all.

The assumption that is left, said plainly: a reply torn across two reads would be
missed and the file would open in a new window. The app writes its fifteen bytes
in one go, so this has not been seen, and it has not been proved impossible
either. The failure is the old behaviour rather than a lost file, which is why it
was judged worth the simplicity.

**A line number: in scope.** `abydos main.go:214`, and `main.go:214:9` too, since
that is what grep and every compiler print — the column is dropped, having nothing
to act on. It cost one field on the wire and a rule in the script, and leaving it
out would have meant somebody pasting a compiler error and getting the top of the
file. A colon is legal in a file name here, so `:214` is a line number only when
the path without it exists and the path with it does not; a file genuinely called
`notes:12` still opens as itself.

**Several files: several tabs, keyboard in the last.** One sequence per file, in
the order they were named, which is what makes the last one the one somebody was
thinking of when they typed the command. Everything is checked before anything is
opened: half of `abydos a.md typo.md` done and then an error is worse than either
outcome on its own.

**A file outside the project: a loose tab in this window.** Not a refusal, and not
taking the window to another project. Somebody typing `abydos ~/notes.md` in a
pane is asking to read it beside what they are working on, not to stop working on
it. The tab bar already marks such a file as external, which is the honest half of
the answer, and this is the same thing the navigator does for a file dropped from
elsewhere.

Two smaller things the entry raised were settled the same way. The panel comes
back to the height it had before it was maximised, and then to half the window if
that height was more — the rule `makeRoomForTheStoppedLine` already used, now
shared and renamed `makeRoomForTheEditor` because it is no longer only the
debugger's. And it **stays** down afterwards: sending it back up when the editor
loses focus would be a mode nobody asked for and would fight with the next click.

## What was seen, and what was not

In the running app, on a real project, typing the command into a real pane:

- **In tmux** (`startsTmux` on, `terminalAtStartup = full`, keystrokes sent into
  the pane through tmux itself): `in-abydos (tty=yes TERM_PROGRAM=tmux tmux=yes
  passthrough=yes)`, `notes.md` open and selected in the tree, the panel back
  from full screen to a split, and the launch harness's new `--report-focus`
  reading `TerminalView` before and `CodeView` after.
- **Outside tmux** (`startsTmux` off): `in-abydos (… tmux=no passthrough=no)`,
  the same three things.
- `abydos deep.txt:150` on line 150; `abydos deep.txt:150 src/main.go` as two
  tabs with the keyboard in `main.go`; `abydos ../outside.md` as a loose tab
  marked external, with the project unchanged.
- The session the app brought up reporting `allow-passthrough on` where before
  the change it reported nothing at all.
- Outside this app, unchanged: a real tmux pane that is not Abydos asks, gets no
  answer, and falls back to `open -a`; with no terminal at all it does not ask.

Not proved:

- **A tmux older than 3.3.** The `-q` that is meant to keep it quiet was tested by
  giving `set-option` a name no tmux knows, not by running an old tmux.
- **A project reached through a symlink opens the file twice.** The command
  resolves with `pwd -P`, so `/private/tmp/x` goes down the pty while the app
  holds `/tmp/x` for the same file, and the two spell different tabs. Seen, on a
  scratch project under `/tmp`; a project under `~` has no symlink to disagree
  about. Which of the two spellings is the right one is a question about tab
  identity generally rather than about this command, and it is left open.
- **A torn-off terminal window.** The path exists and is wired; it was not driven.
- The reply being torn across two reads, above.
