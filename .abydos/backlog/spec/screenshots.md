# Screenshots

## Requirement: A capture is a picture of the app, not of the machine it was taken on

The app photographs itself: `--screenshot <path>` renders the window into a PNG
from its own view tree, in process, which needs no Screen Recording permission
and draws through exactly the code the display uses. It is how the pictures in
`docs/` are made — `Scripts/screenshots.sh` takes every one of them — and how a
change to the interface is looked at without a person at the keyboard.

Everything about a capture that is otherwise remembered per machine is said
outright, because a picture that depends on the machine is a picture nobody else
can take again: the window is given a size, the panel a height, the palette is
named, and each project is copied to a temporary directory first.

What the machine happens to be *doing* is ruled out the same way. A Claude Code
session anywhere on the machine announces itself, through the hook, to every
running copy of the app, and each says so in the corner of its window; a copy
that is taking a picture does not, because whether somebody's agent finished in
the eight seconds before the shutter is not a fact about the program being
photographed.

It is news from outside the run that is declined, not toasts. Everything the run
itself causes still reaches the corner and is still photographed — a shot that
asks for a toast gets one, and a shot that provokes a real failure shows what
the app really says about it — because a capture that quietly left toasts out
could not be told from a capture of an app with nothing to say.

### Scenario: an agent finishes while the picture is being taken

- **Given** two runs of the same capture, on the same project
- **When** a Claude Code hook announces a finished session during the second of
  them, and nothing announces anything during the first
- **Then** the two pictures are identical, byte for byte

### Scenario: a picture of a toast

- **Given** a capture run that asks for a toast
- **Then** the toast is in the picture, in the corner, as it is on screen

### Scenario: the app somebody is working in

- **Given** a capture running while an ordinary window of the app is also open
- **When** a Claude Code hook announces a finished session
- **Then** the ordinary window still says so in its corner
