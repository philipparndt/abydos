## ADDED Requirements

### Requirement: A match band covers the characters it matched, on the row they are drawn on

A find match SHALL be painted over the characters it matched and no others, on the
visual row those characters are drawn on. Under soft wrap the position SHALL be
measured along the visual row being painted, and not along the whole document line.

`searchHighlights` builds one `CTLine` for the whole document line and asks it for the
x of each match. With soft wrap on, a document line is drawn as several visual rows,
each holding a slice of it, so every offset past the first row's end is measured along
a row that is not the one being painted. `CodeView` already knows how to do this —
`firstVisualRow`, `wrapSegmentForOffset` and the wrap layout `updateFrameSize()`
builds are what `point(forUTF16:)` uses to place the caret correctly. The highlight
path predates that and asks the unwrapped line.

That the caret lands correctly and the band does not is the shape of the fault: two
answers to "where is this offset on screen", one of which knows about wrap. This has
been true as long as find-in-file and soft wrap have coexisted; what changed is that
the current match is no longer painted over by the selection, so a band in the wrong
place is now a bright band in the wrong place.

#### Scenario: a match on the second row of a wrapped line

- **Given** soft wrap on, and a document line long enough to occupy several visual rows
- **And** a match whose characters fall on the second visual row
- **When** the line is drawn
- **Then** the band is on the second visual row, over those characters
- **And** nothing is painted on the first row for that match

#### Scenario: several matches on one wrapped line

- **Given** a wrapped line containing `publish` twice and `word` once
- **When** find is searching for `publish`
- **Then** both occurrences of `publish` are banded, and `word` is not

#### Scenario: an unwrapped line

- **Given** soft wrap off, or a line short enough to occupy one visual row
- **When** the line is drawn
- **Then** the bands are where they were before this requirement existed

#### Scenario: a fold above the matched line

- **Given** a collapsed region above the matched line, so the visual rows show
  different document lines than they would unfolded
- **When** the line is drawn
- **Then** the band is still over the characters it matched

### Requirement: A match crossing a wrap boundary is drawn on every row it touches

A match spanning a soft wrap boundary SHALL be painted as one band per visual row it
touches. The band on the first such row SHALL run from the match's start to the end of
that row's text, the band on the last SHALL run from the row's beginning to the
match's end, and any row wholly inside the match SHALL be banded across its text.

The current code cannot express this at all — it has one rectangle per match — so it
is a change in shape rather than in arithmetic, and it is the case most likely to be
got half right.

#### Scenario: a match split across two rows

- **Given** a match beginning near the end of one visual row and ending on the next
- **When** the line is drawn
- **Then** two bands are painted, one on each row
- **And** neither extends past the characters the match covers

#### Scenario: a match spanning three rows

- **Given** a match long enough to cover a whole intervening visual row
- **When** the line is drawn
- **Then** the intervening row is banded across its text, and the first and last rows
  are banded from the match's start and to its end

### Requirement: The caret and a match band agree about where an offset is

The position used to paint a match band SHALL agree with the position used to place
the caret, for the same offset, under soft wrap and under folding.

The caret's answer is already right and already handles folding. A second
implementation that agrees today is how the two came to disagree in the first place,
so whatever is built is either the caret's answer reused or held to it by a test.

#### Scenario: the same offset, asked twice

- **Given** a wrapped line, and an offset on it
- **When** the caret is placed there, and a match begins there
- **Then** the band's left edge is where the caret is
- **And** this holds on every visual row of the line
