# Terminal

The panes in the bottom panel: a real pseudo-terminal each, running the login
shell or one command, with tmux underneath when somebody wants their tabs to be
tmux's windows. A pane is started from the environment the app itself was
launched with, and that is where this file begins. Most of what the app was
launched with is somebody's own and is passed on untouched; a few values describe
the terminal it was launched *from* rather than the one being started, and
passing those on is how a pane comes to lie about where it is or to die before it
draws a prompt.

One requirement so far rather than an account of everything a pane does. The rest
arrives as items touch it.

## Requirement: A pane does not inherit a tmux socket path that could not exist

A shell started here is given the environment the app was launched with, and one
value in it can make tmux impossible before anything has run. `TMUX_TMPDIR` says
where tmux keeps its sockets; tmux appends `tmux-<uid>/default` to it and binds a
unix socket there, and a unix socket path is a fixed-length field — 103 bytes on
macOS, which is what the platform's `sun_path` comes to once the terminator tmux
always writes is taken off. A directory that is merely long therefore produces a
socket that cannot exist, and tmux exits saying `File name too long` about a path
nobody typed.

So the value is measured before it is passed on, against the socket it would
produce rather than against itself: resolved the way tmux resolves it, with what
tmux appends added to it. What does not fit is left out, and the shell is told
what was left out and why, in the pane and in `~/Library/Logs/Abydos/tmux.log` —
because a pane that goes straight into tmux clears its own screen.

What fits is kept, and that is as much the requirement as the refusal. A short,
valid `TMUX_TMPDIR` is somebody's choice about which tmux server their tools
share, and overruling it would put their panes somewhere their other tools cannot
see — the same mistake as ignoring their `PATH`. Nothing is substituted for a
value that is refused, either: tmux has a default of its own, and choosing a
directory here would be the same overruling by another route.

Everything else this app runs tmux for — the tab strip asking a server for its
windows, following a terminal to its pane's directory, hiding the status line,
the Claude hook writing a badge on a window — is given the same environment. Each
of those reports failure as an empty answer, so an inherited value they could not
use made them silent rather than wrong.

### Scenario: a directory too long for the socket it implies

- **Given** the app was launched from a shell with a 116-byte `TMUX_TMPDIR`
- **When** a terminal pane is opened
- **Then** the shell is started without `TMUX_TMPDIR`
- **And** the pane says which variable was left out, what the socket would have
  come to, and what the limit is

### Scenario: a directory short enough to work

- **Given** the app was launched from a shell with `TMUX_TMPDIR=/private/tmp/sockets`
- **When** a terminal pane is opened and runs tmux
- **Then** the shell still has that `TMUX_TMPDIR`
- **And** the server it reaches is the one under that directory

### Scenario: the app asking tmux something of its own

- **Given** a `TMUX_TMPDIR` whose socket path would not fit
- **When** the tab strip asks the server for its windows
- **Then** the question is asked without that `TMUX_TMPDIR`

## Requirement: A pane says how large one of its cells is, and says so again when that changes

A program in a pane cannot measure a cell. The only place the size is written
down is the window size the kernel keeps for the terminal — `TIOCGWINSZ`
carries the grid in cells *and* the pane in pixels, and dividing one by the
other is how `icat`, `timg` and `chafa` decide how many cells a picture needs.
A terminal that leaves the pixels at zero is telling them it cannot show
pictures at all.

So the pane measures a cell in points from the font and multiplies by the
scale of the display it is on — pixels rather than points, because a picture
sized to a Retina cell and drawn at half of it is a soft picture where a sharp
one was asked for. Where there is no window yet, and there is not one when the
font is first measured, the screen is asked instead of a value being assumed:
assuming Retina on a display that is not one halves every cell, and kitty's
`icat` then asks for half the cells the picture needs.

And the number is told again whenever it changes. The window size is one
structure, so writing it used to be the business of a change in the number of
cells alone — which left a pane that learnt its real cell size after its
window appeared reporting the old one until something else happened to resize
it. The same command then produced a picture of one size on the first run and
twice that later, with nothing in between to explain it.

Because the number now reaches the program the moment it is worked out, an
answer that is wrong for a moment is an answer the program acts on. A scale of
zero is such an answer and is not an absent one: a window that is not on a
screen reports zero rather than nothing, and a window is not on a screen while
a display is being woken, unplugged, or moved between. So a scale is used only
if it is positive, and when none of the offered scales is, the size the
program already has is left alone rather than replaced by a guess — the last
answer was worked out on a screen that really existed.

What follows from the true number is not the pane's business to soften. A
picture taller than the pane scrolls as it is written, because `icat` sizes to
the width and never to the height; that is what kitty does with the same file,
and the way to see all of one is to ask for fewer rows.

### Scenario: a cell measured before there is a window

- **Given** a pane on a display whose backing scale is 1
- **When** its font is measured, before the view is in a window
- **Then** the program is told a cell is the size it is on that display,
  rather than twice it

### Scenario: the cell size changes without the grid changing

- **Given** a pane of 24 rows and 80 columns whose cell was reported as 8×19
- **When** the cell is found to be 16×38 and the grid is still 24 by 80
- **Then** the terminal reports 1280 by 912 pixels for the same 24 by 80 cells
- **And** the program is sent `SIGWINCH`, as it is for any other resize

### Scenario: a window that is not on a screen

- **Given** a pane whose window answers a backing scale of zero, and a display
  behind it whose scale is 2
- **When** the cell size is worked out
- **Then** the display's scale is used and the program is told 16×38
- **And** the program is never told a cell is zero pixels, which would be this
  terminal saying it cannot show pictures at all

## Requirement: A picture placed where there is not room for it makes the room

A program placing a picture at the cursor is told nothing about how tall the
pane is, and does not ask. `kitty icat` outside tmux sends the pixel size and
no number of rows at all, and leaves it to the terminal to work out how many
cells that comes to and to move the cursor past them. Making room for those
rows is therefore the terminal's part, exactly as it is when a program prints
that many lines: the rows above go into the scrollback, and the picture ends up
on the screen with the cursor below it.

Clamping the cursor at the last row instead — which is what a cursor *move*
does, and a picture's rows are not a move — leaves the picture standing on rows
below the bottom of the screen. Those rows are never drawn, so the picture is
invisible while the space it took is still spoken for. Worse, they overlap
everything a program erases from below the cursor, and a shell erases from its
prompt down before printing each one: the picture is taken away by the next
prompt. Both halves of "the picture is lost and the gap is kept" are that one
clamp.

This is the same rule the placeholder protocol gets for free. There, a picture
is spelled out in ordinary text and moves when the text moves; a picture placed
at the cursor has to be given the rows deliberately.

### Scenario: a picture taller than what is left below the cursor

- **Given** a pane of 10 rows with the cursor on row 8
- **When** a picture five rows tall is placed at the cursor
- **Then** the screen scrolls three rows, and three lines go into the scrollback
- **And** every row of the picture is on the screen

### Scenario: the prompt after such a picture

- **Given** a picture just placed where there was not room for it
- **When** the shell writes its next prompt, erasing from the cursor downwards
- **Then** the picture is still there

## Requirement: A pane shows what a command printed even if the command has already finished

A pane's process writes to a pseudo-terminal and the pane reads the other end.
On macOS those two are on a clock: **when a child exits, the kernel gives the
terminal's queued output 600 ms to be read, and then discards it.** The child's
own exit is what waits — it reaches `_exit` in under a millisecond and does not
become a zombie for another 600 — and when the wait runs out the controlling
terminal is revoked, the last descriptor on the child's end closes, and closing
it flushes the queue. Nothing is late at that point; the bytes are gone. (Linux
keeps them for the reader, which is why this is easy to write code that only
works there.)

600 ms is a long time and almost always plenty, which is what made this a
half-day of blaming the machine: the pane's reading queue normally takes the
bytes out within microseconds. On a machine with nothing to spare it does not,
and then a `/bin/echo` produces an empty pane rather than a late one. Everything
short is exposed and most of what this app runs through a pane is short — a run
configuration that prints one line and stops, a `git status`, the last of a
container build's progress, an agent that refuses and exits.

So the pane keeps a descriptor of its own on the child's end of the terminal, for
as long as the child runs. The queue is only flushed when the *last* one closes,
and the pane's is still open, so there is no deadline to lose a race against.

**It takes that descriptor before the child exists**, and the order is part of the
requirement rather than an implementation detail. Taking it afterwards — which is
what `forkpty` leaves you to do, since it closes the parent's copy before
returning — leaves a window in which the child can write, exit and lose its output
to a descriptor that is obtained a moment too late. The window is as long as this
process can go unscheduled, which on a loaded machine is longer than 600 ms. So
the terminal is opened, then the child is forked into it: there is no instant at
which a pane's output is unprotected.

This turns a lost-output bug into a lifecycle obligation, and that is the part
worth stating: with the deadline gone, **the child's exit waits for the pane to
read the terminal or close it** rather than for 600 ms. So the pane closes both
descriptors together, once, and only after the reader has finished with them —
and a pane that has stopped reading to apply back-pressure resumes before it
closes. A pane that shut its reader and walked away would leave the process alive
indefinitely, which is worse than the bug this replaced.

It also fixes the order things are announced in. The output a program leaves
behind is delivered before its exit is, because both go through the queue that
reads, and that queue is serial: nothing can announce an exit past a delivery
already in flight. A pane that showed a command's exit above its own output was
showing them in whichever order two queues got threads.

### Scenario: a command that has already finished, on a busy machine

- **Given** a pane running `/bin/echo hello`
- **And** a machine loaded enough that the pane's reader waits longer than 600 ms
  for a thread
- **When** the command has written its line and exited
- **Then** the pane still shows `hello`
- **And** it showed it before it reported the command exiting

### Scenario: a pane that stops reading while its command exits

- **Given** a pane that has suspended reading because it is behind
- **When** its command exits
- **Then** the command's exit completes once the pane reads again or closes
- **And** the pane leaves behind neither the process nor either descriptor
