## MODIFIED Requirement: A selection is drawn gray while the keyboard is somewhere else

Selected text in an editor pane is drawn in the strong highlight only while that
pane has the keyboard. With the keyboard anywhere else — the terminal below, a
results list, another pane of a split — the same selection is still there and is
drawn in a quiet colour instead.

A selection in the strong colour is a claim that the next key will act on it, and
a claim a view makes whether or not it is true is worth nothing. One rule decides
it everywhere — an editor's selected text, a row of a results list and a row of
the project tree all ask the same question — so a window whose keyboard is in the
terminal gives the same answer in every pane at once.

**The quiet colour is not one colour, because a row and a run of text need
different amounts of lift from the same ground.** A row is a band the width of
the pane with an edge above and below it; selected code is a ragged shape mostly
covered by the glyphs sitting on it, and the same colour that reads as a band on
a row disappears behind code. So a row goes to the scheme's `selectionInactive`,
which is what the project tree has used for years, and an editor's text goes to
its `selectionBackgroundInactive`, which every scheme states for itself and which
sits below its own strong highlight — quiet enough not to be mistaken for the
keyboard being here, and never so quiet that a selection has to be looked for.

A scheme that does not state one still gets one: halfway between the two it sits
between, `selectionInactive` and `selectionBackground`. It is the only colour in
a scheme file that may be left out.

The selection is not cleared and nothing else about it changes. It comes back to
the strong colour the moment the pane has the keyboard again, and it is the same
characters that were selected before.

### Scenario: the keyboard goes to the terminal

- **Given** several lines selected in an editor pane
- **When** the keyboard moves to the terminal below it
- **Then** the same lines are still selected, drawn in the quiet colour, and the
  band is still visible against the code it covers

### Scenario: and comes back

- **Given** that quiet selection
- **When** the editor pane is clicked
- **Then** the same lines are selected in the strong highlight again

### Scenario: two panes of a split

- **Given** two editor panes, each with a selection
- **When** one of them has the keyboard
- **Then** only that pane draws its selection in the strong highlight

### Scenario: a row and a run of text in the same window

- **Given** a selected row in the project tree and selected text in an editor,
  with the keyboard in neither
- **Then** the row is drawn in `selectionInactive` and the text in
  `selectionBackgroundInactive`, which is the scheme's stronger of the two
