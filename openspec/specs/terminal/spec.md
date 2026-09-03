# Terminal

## Purpose

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
## Requirements
### Requirement: A pane does not inherit a tmux socket path that could not exist

A pane SHALL NOT inherit a tmux socket path that could not exist.

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

#### Scenario: a directory too long for the socket it implies

- **Given** the app was launched from a shell with a 116-byte `TMUX_TMPDIR`
- **When** a terminal pane is opened
- **Then** the shell is started without `TMUX_TMPDIR`
- **And** the pane says which variable was left out, what the socket would have
  come to, and what the limit is

#### Scenario: a directory short enough to work

- **Given** the app was launched from a shell with `TMUX_TMPDIR=/private/tmp/sockets`
- **When** a terminal pane is opened and runs tmux
- **Then** the shell still has that `TMUX_TMPDIR`
- **And** the server it reaches is the one under that directory

#### Scenario: the app asking tmux something of its own

- **Given** a `TMUX_TMPDIR` whose socket path would not fit
- **When** the tab strip asks the server for its windows
- **Then** the question is asked without that `TMUX_TMPDIR`

### Requirement: A pane says how large one of its cells is, and says so again when that changes

A pane SHALL say how large one of its cells is, and SHALL say so again when that changes.

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

#### Scenario: a cell measured before there is a window

- **Given** a pane on a display whose backing scale is 1
- **When** its font is measured, before the view is in a window
- **Then** the program is told a cell is the size it is on that display,
  rather than twice it

#### Scenario: the cell size changes without the grid changing

- **Given** a pane of 24 rows and 80 columns whose cell was reported as 8×19
- **When** the cell is found to be 16×38 and the grid is still 24 by 80
- **Then** the terminal reports 1280 by 912 pixels for the same 24 by 80 cells
- **And** the program is sent `SIGWINCH`, as it is for any other resize

#### Scenario: a window that is not on a screen

- **Given** a pane whose window answers a backing scale of zero, and a display
  behind it whose scale is 2
- **When** the cell size is worked out
- **Then** the display's scale is used and the program is told 16×38
- **And** the program is never told a cell is zero pixels, which would be this
  terminal saying it cannot show pictures at all

### Requirement: A picture placed where there is not room for it makes the room

A picture placed where there is not room for it SHALL make the room.

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

#### Scenario: a picture taller than what is left below the cursor

- **Given** a pane of 10 rows with the cursor on row 8
- **When** a picture five rows tall is placed at the cursor
- **Then** the screen scrolls three rows, and three lines go into the scrollback
- **And** every row of the picture is on the screen

#### Scenario: the prompt after such a picture

- **Given** a picture just placed where there was not room for it
- **When** the shell writes its next prompt, erasing from the cursor downwards
- **Then** the picture is still there

### Requirement: A pane shows what a command printed even if the command has already finished

A pane SHALL show what a command printed even if the command has already finished.

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

#### Scenario: a command that has already finished, on a busy machine

- **Given** a pane running `/bin/echo hello`
- **And** a machine loaded enough that the pane's reader waits longer than 600 ms
  for a thread
- **When** the command has written its line and exited
- **Then** the pane still shows `hello`
- **And** it showed it before it reported the command exiting

#### Scenario: a pane that stops reading while its command exits

- **Given** a pane that has suspended reading because it is behind
- **When** its command exits
- **Then** the command's exit completes once the pane reads again or closes
- **And** the pane leaves behind neither the process nor either descriptor

### Requirement: A pane can be emulated by libghostty-vt instead of by our own emulator

A pane SHALL be able to be emulated by libghostty-vt instead of by our own emulator.

There are two terminal engines. Ours is the default and is what every terminal
test in the suite was written against. The other is **libghostty-vt** — ghostty's
terminal state machine, with no pty and no renderer of its own — behind the
setting *Use libghostty-vt for the terminal*, which is **off** until somebody has
run it for weeks.

With the setting off nothing changes: the bytes take the identical path through
the identical code, and our emulator does not know the other engine exists.

The choice is made **once per pane**, when the pane is created. An engine holds
the scrollback, the modes and the images, so swapping one out under a running
shell would throw all three away; turning the setting on therefore applies to the
next pane rather than to the one in front of you. If libghostty-vt cannot start,
the pane is emulated by ours rather than by an engine that draws nothing.

Which engine drew a pane is answerable off the running app, because a terminal
bug now has two possible homes and the first question about any report is which
one it was.

#### Scenario: the setting is off

- **Given** the libghostty-vt setting is off
- **When** a terminal pane is opened
- **Then** the pane is emulated by `abydos`
- **And** `--report-geometry` prints `engine=abydos`

#### Scenario: the setting is on

- **Given** the libghostty-vt setting is on
- **When** a terminal pane is opened
- **Then** the pane is emulated by `libghostty-vt`
- **And** `--report-geometry` prints `engine=libghostty-vt`

#### Scenario: the setting is changed while a pane is open

- **Given** an open pane emulated by one engine
- **When** the setting is changed
- **Then** that pane keeps the engine it was made with, with its scrollback and
  its pictures
- **And** the next pane opened uses the other one

### Requirement: An engine says what it cannot do, and the missing parts refuse rather than guess

An engine SHALL say what it cannot do, and the missing parts SHALL refuse rather than guess.

An engine carries a list of what it cannot do, in words fit to show somebody, and
that list is a promise: **anything on it refuses, or is a named difference, rather
than drawing something plausible.** An engine that silently misrenders is worse
than no choice of engine at all, because whoever notices weeks later cannot tell
whether it was the engine, the seam, or a real bug.

Our own engine's list is empty. libghostty-vt's names three things, and each one
of them is either a refusal or a difference stated in advance:

- `abydos <file>` typed in a pane does nothing at all, rather than opening
  something else.
- An ambiguous key sends its ordinary bytes to a program using xterm's older
  `modifyOtherKeys` protocol, rather than a sequence the program did not ask for.
  The kitty keyboard protocol works.
- tmux's own prompts are drawn one row too high when tmux's status bar is off,
  which is the fault item 0404 reported against our emulator and which
  libghostty-vt still has.

#### Scenario: the engine has a gap

- **Given** a pane emulated by libghostty-vt
- **When** the engine is asked what it cannot do
- **Then** every entry names something that refuses or differs, not something
  that is drawn approximately

#### Scenario: a program asks for a file to be opened

- **Given** a pane emulated by libghostty-vt
- **When** `abydos <file>` is typed in it
- **Then** nothing opens
- **And** the engine's list of what it cannot do says so

### Requirement: A picture drawn with unicode placeholders is shown under either engine

A picture drawn with unicode placeholders SHALL be shown under either engine.

`icat` speaks two of the kitty graphics protocol's dialects and tmux decides
which: a real placement outside tmux, and **unicode placeholders** inside it. This
app is used through tmux nearly all the time, so an engine that cannot show a
picture there is not usable.

Under either engine a picture arrives the same way. The cells carry which image
they belong to and which piece of it they are, so everything that moves the
characters moves the picture with them — scrolling, tmux redrawing a pane, a
window getting narrower — because the picture is worked out from where the
characters ended up rather than remembered from where they started.

#### Scenario: a picture inside tmux, under libghostty-vt

- **Given** a pane emulated by libghostty-vt, with a cell size
- **When** an image is transmitted as a virtual placement and placeholder cells
  are written for it
- **Then** the picture is drawn where those characters are, one strip of the image
  per row

#### Scenario: the picture is scrolled into history

- **Given** a picture drawn from placeholder cells
- **When** enough output arrives to push those characters into the scrollback
- **Then** the picture is still that piece of the image, at the row the characters
  are now on

#### Scenario: a PNG, which is what `icat` actually sends

- **Given** a pane emulated by libghostty-vt
- **When** an image is transmitted as PNG
- **Then** it is decoded and held, rather than rejected

### Requirement: A pane draws at the display's rate while a program keeps up, and does not replay a backlog

A pane SHALL draw at the display's rate while a program keeps up, and SHALL NOT replay a backlog.

A pane holds back a redraw when the picture it would draw is **out of date**, and
what says so is time: how long ago the oldest byte nobody has parsed yet was read
off the pseudo-terminal. Under a quarter of a second that is the program's current
picture and it is drawn on every refresh of the display. Over it, the pane is
working through something that has already happened, and drawing every step of it
would be a screen replaying time that has passed — an agent's clock sprinting
through the minutes it spent while a screen was locked. So nothing is drawn for a
quarter of a second, in case the backlog is about to drain and be shown as the one
picture worth having, and after that there is a heartbeat of one picture a second
so that a program which really is outrunning the parser never looks frozen. The
picture drawn when the backlog finally drains is never skipped.

**Seconds, and not "is there anything left to parse".** Those are different
questions with different answers: a program writing as fast as it is read leaves
output queued at every instant, so the second question is permanently answered yes
while every frame it holds back is current. It is also a question whose answer gets
*worse* as the terminal gets faster, because a parser that keeps up reads more per
second and empties its queue less often — which is how making the parser four and a
half times faster stopped the screen. Bytes behind are no better: bytes are only
staleness after dividing by a parse rate, and that rate moves by ten times between
patterns and by several times between releases, so a threshold in bytes means a
different number of seconds for every pattern and every build.

**And the queue that matters is every queue.** Bytes read from the pseudo-terminal
and not yet handed to whatever parses them are as far behind as bytes handed over
and not yet parsed, so the pane counts both and the pty stamps a delivery when it
was *read* rather than when the main thread got round to it. Reads arriving while a
hand-over is still waiting are merged into it, in pieces of at most 128 KB, so there
is only ever one hand-over in flight and the unparsed queue is the only queue there
is. Both halves of that limit matter: with no limit, one delivery grew to several
megabytes and blocked a frame for a quarter of a second; with no merging, an engine
whose cost is per-write rather than per-byte paid it once per kilobyte.

**A program is made to wait when the picture would otherwise fall behind it** — a
tenth of a second of unparsed output is the limit, with a four-megabyte backstop for
a single enormous read. A deeper queue does not parse any faster, so every
millisecond of it is a millisecond the screen is out of date for nothing. This is
also the shorter exposure to the 600 ms the kernel gives a dead child's output: a
pane that stops reading resumes when it is a tenth of a second behind rather than
when four megabytes have been parsed.

#### Scenario: a program producing output as fast as the pane can take it

- **Given** a pane running a program that writes a full screen of colour as fast as
  it is read
- **And** output is therefore queued at every instant
- **When** the pane's picture is a few milliseconds behind what has arrived
- **Then** the screen is drawn on every refresh of the display

#### Scenario: coming back to a pane that ran unwatched

- **Given** a pane holding thousands of frames of a spinner and a clock, produced
  over half an hour while nobody could see them
- **When** the pane works through them
- **Then** the frames in between are not drawn
- **And** what is drawn is a picture a second while it catches up, and the last one
  when it has

#### Scenario: an engine too slow for what the program is writing

- **Given** a pane whose emulator can parse only a fraction of what the program
  produces
- **When** the program keeps writing
- **Then** the program is made to wait rather than the pane queueing output it
  cannot show
- **And** the screen goes on being drawn at the rate the emulator can manage rather
  than once a second

### Requirement: Either engine names the rows that changed, and neither says "all of them" unless they did

Either engine SHALL name the rows that changed, and neither SHALL say "all of them" unless they did.

A pane redraws the rows a program touched rather than the screen, and that is
the difference between a prompt rewritten under a keystroke costing one row and
costing eleven thousand cells. So an engine's answer to "what changed since you
were last asked" is the rows, in the numbering the pane scrolls through, and
**both engines answer it the same way**: our own tracks it as it parses, and
libghostty-vt is asked for the per-row dirtiness it keeps inside its render
state.

Three things still are the whole document, and they are the cases where that is
the truth rather than a shrug:

- A line falling out of the top of history, because that renumbers every row
  below it. Anything remembering what it worked out about a row keeps it under a
  number, and the moment those numbers move is the moment nothing may be kept.
- A program taking the screen over, or handing it back, or resetting the
  terminal. The rows are the same rows and every one of them means a different
  line.
- Anything the engine cannot narrow down — a palette change, a viewport that
  moved. An engine that reports too much draws more than it needed to; one that
  reports too little leaves last minute's text on the screen, and only the second
  is a fault somebody has to notice.

Taking the answer clears it, and a frame drawn for a reason of its own — a
cursor blinking, a window coming forward — is told nothing changed rather than
being handed the rows from the frame before.

#### Scenario: a shell rewrites its prompt line where it already is

- **Given** a pane with a screenful of output and history behind it, under either
  engine
- **When** the program moves the cursor up, clears that line and writes it again
- **Then** the pane is told one row changed
- **And** the rows it had already worked out for every other line are kept

#### Scenario: a line falls out of the top of history

- **Given** a pane whose scrollback is full, under either engine
- **When** enough output arrives to push a line off the top for good
- **Then** the pane is told the whole document changed

#### Scenario: a program takes the screen over

- **Given** a pane running a shell, under either engine
- **When** a full-screen program takes the terminal over, and again when it hands
  it back
- **Then** the pane is told the whole document changed each time

#### Scenario: a frame with nothing new behind it

- **Given** a pane that has just been drawn, under either engine
- **When** it is asked again with no output having arrived in between
- **Then** it is told that nothing changed

### Requirement: How big a terminal is and how much history it has are cheap questions, and asking them does not copy the screen

How big a terminal is and how much history it has SHALL be cheap questions, and asking them SHALL NOT copy the screen.

The pane asks the engine two different kinds of question. **What is on the rows**
is a snapshot: it has to survive whatever the program writes next, so for an
engine that keeps its grid on the far side of a library boundary it means copying
the cells out. **How tall is the document, how far down does the active grid
start, how many lines have gone for good** are numbers every engine already has
to hand.

Those are asked separately, because the pane asks the second kind on the path
that output arrives on — once per delivery, thousands of times a second — and
answering them with a snapshot made libghostty-vt forty times slower in the app
than our own engine while being the faster parser of the two. A snapshot is for
drawing a frame. Nothing on the parse path takes one.

#### Scenario: output arriving while a selection is held

- **Given** a pane with a selection in it, emulated by libghostty-vt, receiving
  output as fast as it can be read
- **When** each delivery is parsed
- **Then** the pane asks only how many lines have been discarded, so that the
  selection can follow them
- **And** no copy of the screen is made for it

### Requirement: A window follows its terminal out of the project, and nowhere else

A window SHALL follow its terminal out of the project, and nowhere else.

A window can be asked to follow its terminal: when the shell in the pane in
front moves to another project, the window changes to that project, keeping
what each had open. What makes that bearable to leave switched on is that
moving *within* a project changes nothing — a `cd` into `Sources` is somebody
going about their work, not somebody leaving.

Within **the project**, which is not the same as within the repository around
it. A project opened at a subdirectory of a checkout — a package inside a
monorepo, one example inside a folder of them — has a repository above it that
answers for every directory in it, including its own. Reading "which repository
is this directory in" as "where has the shell gone" made every such project
throw itself away for the checkout about a second after it was opened, for a
shell that was sitting exactly where it had been put; the tabs somebody had
just opened were replaced by the checkout's own restored session, and nothing
said so.

So the question the window asks is about the project it is on: a directory
inside it is not a move, and only a directory outside it is. A shell that walks
out — `cd ..` into the checkout, or into any other repository — is followed as
it always was, because that is a person navigating rather than the app reading
its own restore back to itself.

A working copy *inside* the project is the exception, and it is a move: it is a
project of its own, and walking into one is walking somewhere else. Without that
exception `.abydos` sets a trap — a folder opened at the home directory is marked
for ever, so every checkout underneath it counts as inside the project and no
`cd` moves the window again.

**Which project a directory belongs to is decided by `.git`, `.svn`, `.hg` and
`.abydos`.** Git is not the only way somebody keeps their work, and a window
that follows a shell between two checkouts and refuses to follow it into a
Subversion working copy is not obeying a rule anybody would recognise — it
looks broken, and there is nothing said to tell the two apart. `.abydos` counts
because it is this application's own record that somebody deliberately opened
this folder as a project, which is a stronger statement about a directory than
any build file in it. A `.svn` naming a working-copy root is told from one
belonging to an interior directory of an old-layout checkout, the way a
submodule's `.git` is told from a worktree's: by what is inside it.

**A folder in none of those is shown, and is not a project.** The tree, the
search and the file index point at it, so following a shell there is worth
something; it has no branch, no run configuration and no session of its own,
and nothing is written into it. This is what a folder is: somewhere to work on
files, arrived at by walking there rather than by being opened. A folder with
nothing above it used to leave the window where it was, which meant that a
shell in a Subversion working copy or in an ordinary directory of notes moved
the window nowhere and said nothing about why.

**And following into one is a setting of its own, off by default.** Following
between projects moves the window when somebody goes to another piece of work,
and a working copy is what says the walk is over. A folder has no such edge:
with this on, `~/Downloads` and `/tmp` are somewhere to follow to, and every
`cd` anywhere is a move. Two different appetites, so two switches — the second
under the first and meaning nothing without it.

Because such a folder is not a project, moving between two of them is not a
project switch: the tree re-points and **every open file stays open**. There is
nothing per-folder to put away and nothing to restore, so there is nothing to
lose. What they share instead is one session, described by the `sessions`
capability.

A directory that is not there is not followed. A shell can be sitting in a
working directory that has been deleted underneath it, and the path it reports
then names nothing; a window that pointed at it would be showing a root it
cannot read.

**The shell's own directory, whatever runs in front of it.** Where a terminal
*is* is where its shell is, and while a command runs that is not where the
command has got to. `brew` changes directory several times over one install; a
build script does the same; reading the foreground process's own answer dragged
the window through every one of them and left it wherever the last happened to
be. The first cure asked only while the shell was waiting, and that traded the
fault for two more: a running script's own project was deselected the moment it
started, and a pane holding something long-lived — a Claude session — never
answered at all, so switching to its tab followed nowhere. So the question is
asked of the shell process itself — its own working directory for a plain pty,
and the pane's `#{pane_pid}`'s for a pane inside tmux — which a command never
moves, a typed `cd` always moves, and which is there to read however long
whatever is in front of it runs.

Nothing somebody types is lost by this: `cd` is a builtin, so the move shows in
the shell's own directory the moment it is made. What is lost is every
directory a command wandered through, which was never a statement about where
the terminal was — while the directory the command was *started from*, which
is one, keeps the project selected for as long as it runs.

**A driven run is the one exception and keeps its own rule: a run given any
launch verb never follows its terminal anywhere.** The window is showing a
project somebody named on the command line, and a pane whose shell sits in a
different checkout would swap it without complaint. Following a terminal is a
gesture, and a driven run has nobody making gestures.

The exception used to be written as "while a screenshot is being taken", and
guarded with `isScreenshotRun` — which is `screenshotPath != nil`. That is
narrower than the sentence it was standing for, and 0534 is what it cost: a run
given `--open`, `--file` and `--print-text` but no `--screenshot` was not a
capture by that test, so the guard let it through, and the window followed a
shell whose working directory had been deleted underneath it into
`~/.config/zshutil`, discarding the tab `--file` had opened. The rule is about a
project somebody named, and every driven run has one.

#### Scenario: a project opened at a subdirectory of a checkout

- **Given** a window following its terminal, opened on `checkout/models`
- **And** its terminal is in `checkout/models`, where the window put it
- **When** the terminal reports where it is
- **Then** the window is still on `checkout/models`, with the tabs it opened

#### Scenario: a shell moving deeper into the project

- **Given** that window, on `checkout/models`
- **When** the shell changes directory to `checkout/models/Sources`
- **Then** the window is still on `checkout/models`

#### Scenario: a shell that really leaves

- **Given** that window, on `checkout/models`
- **When** the shell changes directory to `checkout`
- **Then** the window changes to `checkout` and restores what it had open

#### Scenario: a checkout inside the project the window is on

- **Given** a window on a folder somebody opened at their home directory, which
  is therefore marked as a project
- **When** the shell changes directory into a checkout underneath it
- **Then** the window changes to that checkout

#### Scenario: the checkout the project sits in

- **Given** a window on `checkout/models`
- **When** the shell changes directory to `checkout/models/Sources`
- **Then** the window is still on `checkout/models`, because the checkout that
  answers for that directory is above the project and not inside it

#### Scenario: a submodule inside the project

- **Given** a window on a repository with a submodule at `vendor/thing`
- **When** the shell changes directory into the submodule
- **Then** the window does not move, the submodule belonging to the repository
  around it

#### Scenario: a shell in a Subversion working copy

- **Given** a window following its terminal, on some other project
- **And** a Subversion working copy at `wc`, whose `.svn` names it the root
- **When** the shell changes directory to `wc/trunk/src`
- **Then** the window changes to `wc`, and not to `wc/trunk/src`

#### Scenario: a working copy that keeps metadata in every directory

- **Given** a working copy at `wc` made by a client that writes a `.svn` into
  every directory rather than one at the root
- **When** the shell changes directory to `wc/trunk/src`
- **Then** the window changes to `wc`

#### Scenario: a working copy checked out inside another

- **Given** a working copy at `outer` and another at `outer/inner`
- **When** the shell changes directory to `outer/inner/src`
- **Then** the window changes to `outer/inner`, the nearest of the two

#### Scenario: a shell in a directory that is in no repository

- **Given** that window, on `checkout/models`, and following into folders turned
  on
- **When** the shell changes directory to a folder with no `.git`, `.svn`, `.hg`
  or `.abydos` above it
- **Then** the window shows that folder, with its tree and its search
- **And** the folder is not recorded as a recent project
- **And** nothing is written into the folder

#### Scenario: the same, with the setting off

- **Given** that window, on `checkout/models`, and the default settings
- **When** the shell changes directory to a folder that is in no working copy
- **Then** the window is still on `checkout/models`

#### Scenario: a script that changes directory while it runs

- **Given** a window following its terminal
- **When** a command is run that changes directory several times before it ends
- **Then** the window does not move while it runs
- **And** it does not move when it finishes, the shell being where it was

#### Scenario: a `cd` typed at the prompt

- **Given** the same window
- **When** somebody types `cd` into another checkout
- **Then** the window follows, at the moment they press Return

#### Scenario: a shell moving between two such folders

- **Given** following into folders turned on, and a window showing a folder that
  is in no working copy, with three files open
- **When** the shell changes directory to another folder that is in none either
- **Then** the window shows the second folder
- **And** the three files are still open, in the same tabs

#### Scenario: a shell in a folder inside the project the window is on

- **Given** a window on `notes`, a folder somebody opened by hand
- **When** the shell changes directory to `notes/data`
- **Then** the window is still on `notes`, with the tabs it opened

#### Scenario: a pane brought forward carrying a folder as its root

- **Given** a window following its terminal, showing a folder in no working copy
- **And** a pane created while that folder was showing, so the pane's root is it
- **When** that pane is brought forward
- **Then** the folder is shown as a folder and not as a project
- **And** nothing is written into it, and it is not recorded as a recent

#### Scenario: a shell whose working directory has been deleted

- **Given** a window following its terminal
- **When** a pane reports a working directory that no longer exists
- **Then** the window is where it was

#### Scenario: a driven run that takes no picture

- **Given** a run with `--open <a project> --file main.swift --print-text`, and
  no `--screenshot`
- **And** `followsTerminalProject` is true in the preferences the run copied
- **When** a pane reports a working directory outside the project — because its
  shell inherited a deleted directory and zsh fell back
- **Then** the window is still on the project it was given
- **And** the tab `--file` opened is still open

#### Scenario: a capture, as before

- **Given** a run with `--screenshot`
- **When** a pane reports a working directory in another checkout
- **Then** the window does not follow it

### Requirement: A program started in a pane begins with a signal state of its own

A program started in a pane SHALL begin with a signal state of its own.

The program on the other end of a pane is a child of this process, and two
things it does not want are handed to it for free. A thread's *blocked* signal
mask is inherited by the child of a `fork` and kept across `execve`; a
disposition of `SIG_IGN` is kept across `execve` too. So without saying
otherwise, a shell in a pane starts life holding whatever the app happened to be
holding on the thread that started it.

Both halves are set back to the default between the fork and the exec: every
disposition to `SIG_DFL`, and the mask emptied.

It is not tidiness. This package ignores SIGPIPE process-wide and must — writing
to a pipe nobody is reading kills a process outright otherwise — and a shell that
inherited that ignores it in turn, so `yes | head` in a pane leaves `yes`
running rather than ending it. And a blocked mask is worse, because it makes the
pane's own controls stop working without failing: ⌃C and closing a pane both work
by sending a signal, and a signal that is blocked in the child is not refused, it
is queued for ever. A `/bin/cat` started from a thread with SIGHUP blocked
survives being terminated, is re-parented to `launchd`, and holds its
pseudo-terminal until the machine is restarted (item 0526).

#### Scenario: closing a pane started from a thread that blocks SIGHUP

- **Given** a pane whose program was started on a thread with SIGHUP, SIGINT and
  SIGTERM blocked
- **When** the pane is closed
- **Then** the program receives the hangup and exits, and its pseudo-terminal is
  freed

#### Scenario: a pipeline in a pane

- **Given** a shell in a pane
- **When** it runs a pipeline whose reader exits first
- **Then** the writer is ended by SIGPIPE, as it would be in any other terminal

### Requirement: A pane's pseudo-terminal is not handed to the next program started

A pane's pseudo-terminal SHALL NOT be handed to the next program started.

A pseudo-terminal is freed when the last descriptor on either of its ends is
closed, and until then it counts against `kern.tty.ptmx_max` — 511 for the whole
machine, shared with every terminal, tmux and ssh on it. `openpty` answers with
two ordinary inheritable descriptors, so every program started afterwards —
another pane, a `git`, a language server — takes a copy of both and holds that
terminal open for as long as it runs. Closing the pane frees nothing.

So both ends are marked close-on-exec as soon as they are opened. The pane's own
program is unaffected: it closes the master itself, and `login_tty` puts the
slave onto its standard descriptors with `dup2`, which clears the flag on the
copies.

#### Scenario: two panes, the first closed

- **Given** two panes, opened one after the other
- **When** the first is closed
- **Then** its pseudo-terminal is freed rather than held open by the second
  pane's program

### Requirement: Only the middle button is forwarded as the middle button

The terminal SHALL read which button an `otherMouse` event carries and SHALL
forward only the middle one to the program. macOS raises those events for button
2 — the middle — and for 3 and 4, the side buttons; all three were encoded as
`.middle`, which is button 1 on the wire, so a side button reached the program as
a middle click. Middle click in a terminal is commonly paste, which makes a side
button press over the terminal capable of putting the selection into the shell.

**A button the terminal does not act on SHALL travel up rather than being
consumed.** Both paths returned without calling `super` — the one for a program
that is not tracking the mouse, and the one where the forward is declined — so
these events stopped at the terminal and nothing above it could ever see them.
That is what made the side buttons do nothing over the pane people have open
most.

The middle button's own behaviour SHALL be unchanged, including that a program
which is not tracking the mouse is not sent one.

Side buttons SHALL NOT be forwarded to the program at all: the emulator encodes
left, middle, right, none and the two scroll codes, and has no code for them.

#### Scenario: a side button over a program that tracks the mouse

- **GIVEN** a terminal running a program that has asked for mouse events
- **WHEN** a side button is pressed
- **THEN** the program receives nothing
- **AND** the event reaches the window

#### Scenario: the middle button still pastes where it did

- **GIVEN** the same program
- **WHEN** the middle button is pressed
- **THEN** it is forwarded as the middle button, exactly as before

#### Scenario: a program that is not tracking the mouse

- **WHEN** the middle button is pressed
- **THEN** nothing is sent, as before

### Requirement: A press on a tab's cross closes it, whatever the click count

A click on the close button SHALL close that tab, however quickly it follows the
last one.

Closing four terminals is four clicks in the same corner of the screen, and the
tabs shuffle left under the pointer as they go — so the second, third and fourth
land inside the double-click interval and arrive reported as double clicks. The
strip read the click count first and renamed, so the second press on a cross
opened a rename field on whichever tab had just slid into that place, and the
terminal somebody meant to close was still there with its name selected. Nobody
has ever meant to rename a tab by hitting the one control on it that is not its
name.

Double-clicking a tab anywhere else SHALL still rename it in place, and
double-clicking the empty part of the strip SHALL still give the panel the
window.

#### Scenario: closing four terminals in a row

- **GIVEN** five terminal tabs
- **WHEN** the close button is clicked four times in quick succession, without
  the pointer moving
- **THEN** four tabs are closed
- **AND** no rename field opens

#### Scenario: renaming still works

- **GIVEN** a terminal tab
- **WHEN** it is double-clicked away from its cross
- **THEN** its name becomes editable in place

### Requirement: The panel's own controls are drawn on a ground of their own

The panel's controls SHALL be drawn on an opaque ground, so that a tab running
under them is hidden rather than showing through.

The tabs of a strip are laid out from its leading edge at whatever width each
name needs, and the controls — the running-sessions pill, the session tag,
follow, maximise, hide — are placed backwards from its trailing edge. With
enough tabs open the two meet: with a dozen terminals open the session tag was a
translucent pill with a tab's name legible underneath it and the glyphs
overlapping the names either side. This is the editor tab bar's own settled
answer to the same collision — a tab's last few characters matter less than the
controls staying readable and reachable.

The running-sessions pill is the leftmost of the controls and so the first the
tabs meet. It SHALL take no room when it is not drawn, so a panel with no
running session gives the tabs what the pill would have had.

A tab hidden this way SHALL still be reachable, which is the other half and is
covered by the tab-overflow capability.

#### Scenario: a strip with more tabs than room

- **GIVEN** a panel strip whose tabs reach the trailing edge
- **WHEN** it is drawn
- **THEN** the controls are legible against their own ground
- **AND** no tab name is drawn through them

#### Scenario: a strip with more tabs than room and sessions running

- **GIVEN** a panel strip whose tabs reach the trailing edge
- **AND** a running session on the machine, so the pill is drawn
- **WHEN** it is drawn
- **THEN** the pill's counts are legible against their own ground
- **AND** the tab that reached it is hidden under it, not drawn through it

#### Scenario: nothing running

- **GIVEN** no running session on the machine
- **WHEN** the strip is laid out
- **THEN** no room is reserved for the pill, and the tabs run to the session tag

### Requirement: A pane says which engine drew it

A pane SHALL be able to say which engine drew it, read from the engine it holds
rather than from the setting that asked for one.

Three facts are true separately and were indistinguishable: the setting is on;
*this pane* uses that engine; and that engine started. A pane picks its engine
when it is built, so a pane older than a setting change keeps what it was made
with — deliberately, because a running shell would lose its scrollback
otherwise — and a libghostty-vt that will not initialise falls back to our own
emulator, which is right and silent. So "I turned it on and I cannot tell" has
three possible true answers, and the app offered no way to choose between them.

**The non-default engine SHALL be what is shown.** A mark present in the
ordinary case is a mark nobody reads.

**A fallback SHALL be audible once.** Somebody who asked for libghostty-vt and
got our emulator because the library would not start SHALL hear it, rather than
discovering it in a launch flag.

#### Scenario: a pane drawn by the non-default engine

- **GIVEN** the setting on, and a pane opened after it was changed
- **THEN** the pane says libghostty-vt drew it

#### Scenario: a pane older than the setting

- **GIVEN** a pane opened before the setting was changed
- **THEN** it says our own emulator drew it, which is what it has

#### Scenario: the ordinary case

- **GIVEN** the setting off
- **THEN** nothing is marked

#### Scenario: the library will not start

- **GIVEN** the setting on and a libghostty-vt that fails to initialise
- **WHEN** a pane is opened
- **THEN** the fallback is said once
- **AND** the pane says our own emulator drew it

### Requirement: A pane claims a capable terminal and does not disable the pager

The environment a pane is started with SHALL claim a capable terminal — `TERM`,
`COLORTERM` and `LANG` — and SHALL NOT set `PAGER`.

A program's behaviour when its output is long is the program's own: `git log`
opens `less` with git's `LESS=FRX`, which quits by itself when the output fits a
screen, and `man` and the rest behave as they do in every other terminal.

`PAGER` was set to `cat` here, to stop a pager hanging a pane waiting for a
keypress. That was true of a terminal that could not run a full-screen program;
this one runs `vim`, `htop`, `claude`'s own full-screen UI and tmux, and a pager
is that same class of program. The old default was also invisible where it hurt:
nothing on screen said `PAGER` had been chosen for you, so `git log` printing
everything read as this terminal being broken — which is how it was reported.

An environment given to a pane explicitly, and a `PAGER` in it, SHALL be left
alone: claiming a capable terminal is not overruling a choice. A `PAGER` the app
inherits from whatever launched it is such a choice and SHALL reach the pane
too.

A tmux server that is already running SHALL have this app's own `PAGER=cat`
taken out of its global environment at launch, and only that value. tmux hands
its global environment to every window it makes for the rest of the server's
life — weeks — so a server first started by a pane of this app goes on handing
out `cat` after the line that set it is gone. Anything other than `cat` is
somebody's own choice and is left.

#### Scenario: git log in a pane

- **GIVEN** a repository with more history than fits a screen
- **WHEN** `git log` is run in a pane
- **THEN** a pager is showing, and `q` leaves it with the prompt back

#### Scenario: a server that was started with the old value

- **GIVEN** a running tmux server whose global environment holds `PAGER=cat`
- **WHEN** the app launches
- **THEN** that variable is unset in the server, and a pane on it pages

#### Scenario: a pager somebody chose

- **GIVEN** an environment carrying `PAGER`
- **WHEN** a pane is started with it
- **THEN** that value is what the pane has

### Requirement: The panel keeps the height it was given

The terminal panel SHALL keep its height when the window's width changes, and
SHALL be left at the height it was asked for when it is rounded down to whole
terminal rows.

Rounding to whole rows SHALL be a fixed point: applying it once SHALL leave
nothing more to round. A `NSSplitView` gives its second subview
`total − position − dividerThickness`, so a divider position computed without
the thickness leaves the panel a point short of what was wanted, the terminal's
usable height a point short of whole rows, and a remainder of nearly a whole row
for the next pass to take off again. Widening a window posts one resize
notification after another, and the panel lost a row to each of them until it
reached its floor.

A resize in which the split's height did not change SHALL NOT move the divider.

#### Scenario: widening the window

- **GIVEN** a panel at some height
- **WHEN** the window is made wider without changing its height
- **THEN** the panel still has that height

#### Scenario: rounding to whole rows settles

- **GIVEN** a panel whose terminal has part of a row left over
- **WHEN** the rounding is applied
- **THEN** the panel is the height that was asked for, and asking again says
  there is nothing to round

### Requirement: Next Tab and Previous Tab follow the keyboard

*Next Tab* (⌘⇧]) and *Previous Tab* (⌘⇧[) SHALL, while the keyboard is in the
panel, select the neighbouring tab on the strip of the column being typed in,
wrapping at either end, and SHALL give that tab the keyboard as a click on it
does. While the keyboard is in the editor they SHALL act on the editor's tabs, as
they always have.

Where tmux's windows have a strip of their own along the bottom, the top strip's
tabs — the `tmux` tab and the panel's own terminals and panes — are what the keys
move between, and tmux's windows keep tmux's own keys; a top strip holding a
single tab over such a strip SHALL cycle the windows instead, since those are
the tabs on show. Where tmux's windows share the one strip, they are among the
tabs the keys move between.

#### Scenario: from a terminal to the tmux tab and back

- **GIVEN** a panel strip holding `tmux`, `Local`, `Local`, with the keyboard in the second `Local`
- **WHEN** ⌘⇧] is pressed
- **THEN** the `tmux` tab is in front and has the keyboard
- **WHEN** ⌘⇧[ is pressed
- **THEN** the second `Local` is in front again

#### Scenario: the editor keeps its keys

- **GIVEN** the same panel, with the keyboard in the editor
- **WHEN** ⌘⇧] is pressed
- **THEN** the editor's next tab is in front and the panel's strip is unchanged

#### Scenario: only the tmux tab over its own strip

- **GIVEN** a top strip holding only `tmux`, with tmux's windows on a strip below it
- **WHEN** ⌘⇧] is pressed with the keyboard in the terminal
- **THEN** the next tmux window is selected

### Requirement: A glyph that reaches past its cell is drawn whole

The pane SHALL draw a glyph that reaches past its cell whole, under either
renderer, whatever the cell after it holds; and a cell's background colour SHALL
stop at the cell's own edge.

A glyph may be wider than its cell: a descender or an accent by a little, a
symbol from a fallback font by nearly a cell — swift-testing's pass and fail
marks are 13.7 points wide at a 13-point size against a 7.8-point cell. Counting
it two columns would misplace everything after it, which tmux and Ghostty do not
do; so it spills, and what it spills into must not be painted over it
afterwards.

#### Scenario: swift-testing's marks

- **GIVEN** a pane drawn by the GPU renderer showing `􀟈  Test one`
- **WHEN** the drawable is captured
- **THEN** the diamond is whole, both halves, with the two spaces after it

#### Scenario: a coloured cell beside a plain one

- **GIVEN** a cell with a coloured background whose glyph leans into the plain cell to its right
- **WHEN** the pane is drawn
- **THEN** the colour ends at the cell's edge and the glyph's overhang shows the plain cell's colour around it

### Requirement: A pane names itself to what runs in it

Every shell the panel starts SHALL find `ABYDOS_TERMINAL` in its environment,
set to the identity of the tab it runs in — set, as `TERM_PROGRAM` is, rather
than inherited, since an inherited value would name the tab the app itself was
launched from.

A program in that pane can then say which tab it is in: the Claude hook sends
the value with its events when it is not inside tmux, and the running-sessions
list uses it to bring the tab forward. Inside tmux the variable is the tmux
server's inheritance and is not sent; the tmux place is.

#### Scenario: a shell in the second tab

- **GIVEN** two `Local` tabs
- **WHEN** `echo $ABYDOS_TERMINAL` is run in the second
- **THEN** it prints the second tab's identity, and the first tab's shell prints a different one

#### Scenario: a hook outside tmux

- **GIVEN** a Claude session started in a `Local` tab
- **WHEN** it sends an event
- **THEN** the event carries the tab's identity and no tmux place

