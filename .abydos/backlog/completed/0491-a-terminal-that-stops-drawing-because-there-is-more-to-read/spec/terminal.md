## ADDED Requirement: A pane draws at the display's rate while a program keeps up, and does not replay a backlog

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
