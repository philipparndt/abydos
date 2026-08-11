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
