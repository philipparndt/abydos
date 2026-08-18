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

## Requirement: A pane can be emulated by libghostty-vt instead of by our own emulator

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

### Scenario: the setting is off

- **Given** the libghostty-vt setting is off
- **When** a terminal pane is opened
- **Then** the pane is emulated by `abydos`
- **And** `--report-geometry` prints `engine=abydos`

### Scenario: the setting is on

- **Given** the libghostty-vt setting is on
- **When** a terminal pane is opened
- **Then** the pane is emulated by `libghostty-vt`
- **And** `--report-geometry` prints `engine=libghostty-vt`

### Scenario: the setting is changed while a pane is open

- **Given** an open pane emulated by one engine
- **When** the setting is changed
- **Then** that pane keeps the engine it was made with, with its scrollback and
  its pictures
- **And** the next pane opened uses the other one

## Requirement: An engine says what it cannot do, and the missing parts refuse rather than guess

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

### Scenario: the engine has a gap

- **Given** a pane emulated by libghostty-vt
- **When** the engine is asked what it cannot do
- **Then** every entry names something that refuses or differs, not something
  that is drawn approximately

### Scenario: a program asks for a file to be opened

- **Given** a pane emulated by libghostty-vt
- **When** `abydos <file>` is typed in it
- **Then** nothing opens
- **And** the engine's list of what it cannot do says so

## Requirement: A picture drawn with unicode placeholders is shown under either engine

`icat` speaks two of the kitty graphics protocol's dialects and tmux decides
which: a real placement outside tmux, and **unicode placeholders** inside it. This
app is used through tmux nearly all the time, so an engine that cannot show a
picture there is not usable.

Under either engine a picture arrives the same way. The cells carry which image
they belong to and which piece of it they are, so everything that moves the
characters moves the picture with them — scrolling, tmux redrawing a pane, a
window getting narrower — because the picture is worked out from where the
characters ended up rather than remembered from where they started.

### Scenario: a picture inside tmux, under libghostty-vt

- **Given** a pane emulated by libghostty-vt, with a cell size
- **When** an image is transmitted as a virtual placement and placeholder cells
  are written for it
- **Then** the picture is drawn where those characters are, one strip of the image
  per row

### Scenario: the picture is scrolled into history

- **Given** a picture drawn from placeholder cells
- **When** enough output arrives to push those characters into the scrollback
- **Then** the picture is still that piece of the image, at the row the characters
  are now on

### Scenario: a PNG, which is what `icat` actually sends

- **Given** a pane emulated by libghostty-vt
- **When** an image is transmitted as PNG
- **Then** it is decoded and held, rather than rejected

## Requirement: A pane draws at the display's rate while a program keeps up, and does not replay a backlog

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

### Scenario: a program producing output as fast as the pane can take it

- **Given** a pane running a program that writes a full screen of colour as fast as
  it is read
- **And** output is therefore queued at every instant
- **When** the pane's picture is a few milliseconds behind what has arrived
- **Then** the screen is drawn on every refresh of the display

### Scenario: coming back to a pane that ran unwatched

- **Given** a pane holding thousands of frames of a spinner and a clock, produced
  over half an hour while nobody could see them
- **When** the pane works through them
- **Then** the frames in between are not drawn
- **And** what is drawn is a picture a second while it catches up, and the last one
  when it has

### Scenario: an engine too slow for what the program is writing

- **Given** a pane whose emulator can parse only a fraction of what the program
  produces
- **When** the program keeps writing
- **Then** the program is made to wait rather than the pane queueing output it
  cannot show
- **And** the screen goes on being drawn at the rate the emulator can manage rather
  than once a second

## Requirement: Either engine names the rows that changed, and neither says "all of them" unless they did

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

### Scenario: a shell rewrites its prompt line where it already is

- **Given** a pane with a screenful of output and history behind it, under either
  engine
- **When** the program moves the cursor up, clears that line and writes it again
- **Then** the pane is told one row changed
- **And** the rows it had already worked out for every other line are kept

### Scenario: a line falls out of the top of history

- **Given** a pane whose scrollback is full, under either engine
- **When** enough output arrives to push a line off the top for good
- **Then** the pane is told the whole document changed

### Scenario: a program takes the screen over

- **Given** a pane running a shell, under either engine
- **When** a full-screen program takes the terminal over, and again when it hands
  it back
- **Then** the pane is told the whole document changed each time

### Scenario: a frame with nothing new behind it

- **Given** a pane that has just been drawn, under either engine
- **When** it is asked again with no output having arrived in between
- **Then** it is told that nothing changed

## Requirement: How big a terminal is and how much history it has are cheap questions, and asking them does not copy the screen

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

### Scenario: output arriving while a selection is held

- **Given** a pane with a selection in it, emulated by libghostty-vt, receiving
  output as fast as it can be read
- **When** each delivery is parsed
- **Then** the pane asks only how many lines have been discarded, so that the
  selection can follow them
- **And** no copy of the screen is made for it

## Requirement: A press on a tab's cross closes it, whatever the click count

A click on the close button SHALL close that tab, however quickly it follows the
last one. Closing four terminals is four clicks in the same corner of the screen,
and the tabs shuffle left under the pointer as they go — so the second, third and
fourth land inside the double-click interval and arrive reported as double
clicks.

The strip read the click count first and renamed, so the second press on a cross
opened a rename field on whichever tab had just slid into that place, and the
terminal somebody meant to close was still there with its name selected. Nobody
has ever meant to rename a tab by hitting the one control on it that is not its
name.

Double-clicking a tab anywhere else still renames it in place, and
double-clicking the empty part of the strip still gives the panel the window.

### Scenario: closing four terminals in a row

- **GIVEN** five terminal tabs
- **WHEN** the close button is clicked four times in quick succession, without
  the pointer moving
- **THEN** four tabs are closed
- **AND** no rename field opens

### Scenario: renaming still works

- **GIVEN** a terminal tab
- **WHEN** it is double-clicked away from its cross
- **THEN** its name becomes editable in place

## Requirement: The panel's own controls are drawn on a ground of their own

The tabs of a strip are laid out from its leading edge at whatever width each
name needs, and the panel's controls — the session tag, follow, maximise, hide —
are placed backwards from its trailing edge. With enough tabs open the two meet.

The controls SHALL be drawn on an opaque ground so that a tab running under them
is hidden rather than showing through: with a dozen terminals open the session
tag was a translucent pill with a tab's name legible underneath it and the glyphs
overlapping the names either side. This is the editor tab bar's own settled
answer for the same collision — a tab's last few characters matter less than the
controls staying readable and reachable.

**A tab hidden this way is still reachable**, which is the other half and has its
own requirement.

### Scenario: a strip with more tabs than room

- **GIVEN** a panel strip whose tabs reach the trailing edge
- **WHEN** it is drawn
- **THEN** the controls are legible against their own ground
- **AND** no tab name is drawn through them

## Requirement: A tab that does not fit is still reachable

A strip SHALL offer every tab it holds however narrow the window is. Both strips
laid their tabs out from the leading edge with no bound and neither takes a
scroll wheel, so a tab past the trailing edge could be reached by widening the
window or by closing the ones in front of it — and for the panel's strip that was
the whole list, since ⌘] and ⌘[ are `editor.selectNextTab`.

Where tabs do not fit, a chevron at the trailing end SHALL say how many are
hidden and list them. **The count is not decoration**: three hidden and eleven
hidden are different situations, and it is what makes the control visible among
four other glyphs. Where they all fit there SHALL be no chevron.

Only the hidden ones are listed. A list of everything is a tab switcher, which is
a different feature with a different gesture, and it would put the tab somebody
is looking at into a menu of things they cannot see. Each entry carries what the
tab itself cannot: tmux's number for a window, or the position along the strip,
because sixteen terminals are sixteen tabs called `Local`.

**A tab is visible only if the whole of it is**, in front of the ground the
controls are drawn on. Half a tab under the session tag is not a target.

**The active tab is always wholly visible.** The run of drawn tabs moves forward
for that reason and no other — not on a wheel, not on a drag, not remembered
between launches — and by the least that brings it into view. Where the run has
moved, tabs are hidden before it as well as after it, and both are counted and
listed, in tab order.

**And it moves back whenever there is room going spare at the trailing end.**
Reported: eight tabs left after closing several, room for all of them, half the
strip empty, and the chevron still offering five. The run only ever moved forward
and nothing brought it back, so space that appeared later went unused — the same
fault whether tabs are closed or the window is widened. It settles only into
trailing space, so a run with tabs still hidden after it is left exactly where it
is, which is every moment somebody is working in the middle of a long strip.

**A hidden tab is not drawn at all.** It has no rectangle, and an empty rectangle
is the origin — the top-left corner of the strip — so every tab scrolled out of
the run painted its icon there, stacked behind the first visible one. That is the
clutter that appeared above the first tab.

### Scenario: closing tabs until they all fit

- **GIVEN** a strip whose run has been pushed forward, with tabs hidden before it
- **WHEN** enough tabs are closed that the rest would fit
- **THEN** the run returns to the start, every tab is shown, and there is no
  chevron

### Scenario: the leading edge of a strip with hidden tabs

- **GIVEN** a run with tabs hidden before it
- **WHEN** the strip is drawn
- **THEN** nothing of those tabs appears at the leading edge

Which tab the run starts at is remembered by name and not by number. This strip
mirrors tmux's window list and is rebuilt whenever that is re-read: a window
closed in another client shifts every index after it. A tab that has gone puts
the run back at the first.

### Scenario: twenty-seven terminals in one window

- **GIVEN** a strip holding twenty-seven tabs with room for sixteen
- **WHEN** it is drawn
- **THEN** the chevron says eleven are hidden
- **AND** its menu lists those eleven, numbered, in tab order

### Scenario: choosing one that could not be seen

- **GIVEN** that menu, with the run scrolled to the end
- **WHEN** the first hidden tab is chosen
- **THEN** it is active and wholly visible
- **AND** the tabs now hidden are the ones past the other end

### Scenario: a strip with room to spare

- **GIVEN** a strip whose tabs all fit
- **WHEN** it is drawn
- **THEN** there is no chevron at all


## Requirement: A window follows its terminal out of the project, and nowhere else

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
its own restore back to itself. A directory belonging to no repository at all
leaves the window where it is.

A capture is the one exception and keeps its own rule: while a screenshot is
being taken the window never follows its terminal anywhere, because the picture
is of a project somebody named on the command line and a pane restored into a
different checkout would swap it without complaint.

### Scenario: a project opened at a subdirectory of a checkout

- **Given** a window following its terminal, opened on `checkout/models`
- **And** its terminal is in `checkout/models`, where the window put it
- **When** the terminal reports where it is
- **Then** the window is still on `checkout/models`, with the tabs it opened

### Scenario: a shell moving deeper into the project

- **Given** that window, on `checkout/models`
- **When** the shell changes directory to `checkout/models/Sources`
- **Then** the window is still on `checkout/models`

### Scenario: a shell that really leaves

- **Given** that window, on `checkout/models`
- **When** the shell changes directory to `checkout`
- **Then** the window changes to `checkout` and restores what it had open

### Scenario: a shell in a directory that is in no repository

- **Given** that window, on `checkout/models`
- **When** the shell changes directory to a folder with no repository above it
- **Then** the window is still on `checkout/models`

## Requirement: A program started in a pane begins with a signal state of its own

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

### Scenario: closing a pane started from a thread that blocks SIGHUP

- **Given** a pane whose program was started on a thread with SIGHUP, SIGINT and
  SIGTERM blocked
- **When** the pane is closed
- **Then** the program receives the hangup and exits, and its pseudo-terminal is
  freed

### Scenario: a pipeline in a pane

- **Given** a shell in a pane
- **When** it runs a pipeline whose reader exits first
- **Then** the writer is ended by SIGPIPE, as it would be in any other terminal

## Requirement: A pane's pseudo-terminal is not handed to the next program started

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

### Scenario: two panes, the first closed

- **Given** two panes, opened one after the other
- **When** the first is closed
- **Then** its pseudo-terminal is freed rather than held open by the second
  pane's program
