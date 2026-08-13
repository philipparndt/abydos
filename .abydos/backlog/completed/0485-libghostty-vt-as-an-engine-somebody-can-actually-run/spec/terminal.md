<!-- What this item changes about `terminal`. Folded into
     .abydos/backlog/spec/terminal.md by `abydos-backlog done`.

     ADDED, MODIFIED and REMOVED. A rename is a REMOVED and an ADDED.
     Write each requirement as it will read in the spec, in the present
     tense — not as a description of the edit.
     The requirements already there, to name exactly:
       A pane does not inherit a tmux socket path that could not exist
       A pane says how large one of its cells is, and says so again when that changes
       A picture placed where there is not room for it makes the room
       A pane shows what a command printed even if the command has already finished
-->

## ADDED Requirement: A pane can be emulated by libghostty-vt instead of by our own emulator

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

## ADDED Requirement: An engine says what it cannot do, and the missing parts refuse rather than guess

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

## ADDED Requirement: A picture drawn with unicode placeholders is shown under either engine

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
