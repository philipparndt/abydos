<!-- What this item changes about `editor`. Folded into
     .abydos/backlog/spec/editor.md by `abydos-backlog done`. -->

## ADDED Requirement: A place the editor is sent to is on the screen when it gets there

Something outside the editor — a search result, a usage, a review finding, a
symbol from the palette, `abydos main.go:214`, the line a debugger stopped on —
asks for a place in a file, and the editor shows it. Showing it means it is
**within the pane** when the scrolling stops, both down the page and across it.

The pane is measured, not guessed. Everything the answer is worked out from is a
property of a laid-out view — where a line falls once folding and soft wrap are
accounted for, how tall the viewport is, how wide the text column is inside its
gutter — so the reveal makes the layout pass happen before it measures, rather
than running a turn of the main loop later and hoping it has. A turn of the main
loop is not "the pane has been laid out"; it is a turn of the main loop, and a
reveal that bets on one is right most of the time and wrong the rest, which is
what "sometimes off the screen" was.

Where there is still nothing to measure — a tab whose window is not on screen
yet, a pane the layout pass has not reached — the reveal **waits for the pane to
be given a size** and happens then. It does not scroll to a position computed
from a viewport of no height, and it does not retry on a timer: what it waits for
is the event that means "you have a size now".

**Vertically**, a line that has to be brought in is centred, so there is context
around what was jumped to. A line that is already on screen is shown by leaving
the view where it is — with the top row and the bottom two counting as off screen,
because a line drawn half over an edge is not one anybody can read.

**Horizontally**, what is being pointed at is brought inside the text column with
a little context beside it, and the offset is left alone when it is already
inside. This is not "scroll to the column": a match eighty characters along its
line does not push the start of that line off the left edge for no reason. Text
under the gutter counts as off the screen, because the gutter is drawn over the
viewport's left edge rather than over the text. Where soft wrap is on there is
nothing to scroll sideways and the pane stays against the left edge.

A match is a **span and not a point**: how wide it is comes with it, so one that
starts a column inside the right edge and runs past it is brought in rather than
called visible on the strength of its first character. One longer than the pane
is wide is shown from its start, because what is read is read from the beginning.

### Scenario: a search result in a file that has just been opened

- **Given** a result in a file with no tab open, in a project search
- **When** the row is shown
- **Then** the file opens, the caret is on the match, and the match is inside the
  pane — however many turns of the main loop the opening took

### Scenario: walking a file's matches with ↓

- **Given** three matches within a screenful of each other
- **When** the selection is moved onto each of them in turn
- **Then** the first is brought on screen and the view does not move again for the
  other two

### Scenario: a match far along a long line

- **Given** a match at column 262 of a 294-character line, in a pane about a
  hundred columns wide
- **When** it is revealed
- **Then** the pane is scrolled sideways until the match and some of what follows
  it are visible, and the whole match is on the screen rather than its first
  character

### Scenario: a match already visible on a long line

- **Given** a pane scrolled sideways, with the next match inside the text column
- **When** that match is revealed
- **Then** neither offset changes

### Scenario: a reveal asked for before the pane has a size

- **Given** a reveal on a pane whose viewport has no height yet
- **When** the pane is given its size
- **Then** the place asked for is brought on screen at that moment, and nothing
  was scrolled in the meantime
