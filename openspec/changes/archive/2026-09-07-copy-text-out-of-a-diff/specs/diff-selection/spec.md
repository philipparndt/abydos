## Purpose

What a gesture in a diff selects — text by character over the code, whole lines
over the numbers — what the selection is drawn as, and what it puts on the
clipboard when it is copied. A diff is the one place in this window where code
is read and could not be taken away, and this is the capability that says it
can.

## ADDED Requirements

### Requirement: Text in a diff is selected by dragging over it

A press and drag over the text of a diff SHALL select that text by character,
from where the press landed to where the pointer is, across as many rows as the
drag covers.

A diff is code, and code is read in order to be quoted: into a remark, into a
search field, into a terminal, into another file. Every other view in this
window that shows code can be selected and copied; the diff could not, and a
reader's conclusion from that was that the diff was a preview of a file rather
than the file.

A press with no drag selects nothing and puts the caretless selection away — a
click is how a selection is dismissed, not how one is made.

#### Scenario: a run of characters on one row

- **GIVEN** a diff whose row for line 12 reads `let text = try String(contentsOf: url)`
- **WHEN** the pointer presses over the `t` of `try` and drags to the end of `String`
- **THEN** `try String` is selected, and nothing on any other row is

#### Scenario: across several rows

- **GIVEN** a diff with lines 12, 13 and 14 on consecutive rows
- **WHEN** a drag runs from the middle of line 12 to the middle of line 14
- **THEN** the selection is the tail of line 12, the whole of line 13 and the
  head of line 14

#### Scenario: shift extends what is already selected

- **GIVEN** a text selection over line 12
- **WHEN** the pointer is shift-clicked on line 15
- **THEN** the selection runs from where it began to that point on line 15

#### Scenario: a click puts it away

- **GIVEN** a text selection over three rows
- **WHEN** the pointer is clicked once over the text with nothing dragged
- **THEN** nothing is selected and nothing is highlighted

### Requirement: ⌘C copies the selection, and so does the menu

⌘C SHALL copy the text selection, and *Copy* SHALL be offered as the first item
of the menu over a diff whenever there is one. The Edit menu's *Copy* SHALL be
enabled when the diff has the keyboard and something in it is selected, and
disabled when nothing is.

⌘C is asked of a diff by every hand that arrives at one; a view that answers it
with nothing is indistinguishable from a picture.

#### Scenario: the keyboard shortcut

- **GIVEN** a text selection over a diff that has the keyboard
- **WHEN** ⌘C is pressed
- **THEN** the clipboard holds the selected text

#### Scenario: the menu over the diff

- **GIVEN** a text selection
- **WHEN** the menu is opened over the diff
- **THEN** its first item is *Copy*

#### Scenario: nothing selected

- **GIVEN** a diff with the keyboard and nothing selected
- **THEN** the Edit menu's *Copy* is disabled, and the menu over the diff offers
  no *Copy*

### Requirement: What is copied is the code, without the diff's furniture

Copied text SHALL be the characters of the lines themselves: no line numbers, no
`+` or `-` marker, and no gutter. Rows SHALL be joined by a single newline, and
a partly covered row SHALL contribute only the characters the selection covers.

The reason to copy out of a diff is to paste code somewhere that expects code —
a terminal, a search field, a file. A leading `+` makes every pasted line wrong,
and a line number makes it twice wrong. It is also what makes the two
arrangements agree: side by side draws no marker at all, so dropping it is the
only way a selection copies the same characters in both.

#### Scenario: an added line

- **GIVEN** a unified diff whose row reads `+    let text = try read(url)` at
  new-side line 12
- **WHEN** the whole row is selected and copied
- **THEN** the clipboard holds `    let text = try read(url)` — the indent kept,
  the marker and the number not

#### Scenario: the same selection in the other arrangement

- **GIVEN** the same diff shown side by side
- **WHEN** the same row is selected and copied
- **THEN** the clipboard holds exactly the same characters

#### Scenario: several rows

- **GIVEN** a selection covering a removed line and the added line under it
- **WHEN** it is copied
- **THEN** the clipboard holds both lines' text, in the order they are drawn,
  separated by one newline, with neither marker

#### Scenario: a hunk header inside the selection

- **GIVEN** a selection that runs from a line above a hunk header to a line below it
- **WHEN** it is copied
- **THEN** the header's own text is one of the lines on the clipboard, as it is
  drawn

### Requirement: A line selection with no text selection is copied as its lines

Where nothing is selected as text but a run of lines is selected, ⌘C SHALL copy
those lines' text, under the same rules as a text selection.

A selection that is visibly on the screen and copies nothing is the complaint
this capability exists to answer, and it does not matter which of the two
selections it is.

#### Scenario: lines selected in the number column

- **GIVEN** lines 12 to 14 selected in the number column and no text selection
- **WHEN** ⌘C is pressed
- **THEN** the clipboard holds those three lines' text, one per line, without
  markers or numbers

#### Scenario: a text selection wins

- **GIVEN** a run of lines selected and then a word selected as text
- **WHEN** ⌘C is pressed
- **THEN** the clipboard holds the word, because it is what was selected last

### Requirement: Whole lines are selected in the number column

A press or drag over the line-number column of a diff SHALL select whole lines —
the selection that stages, discards, stashes and carries a remark — and a press
or drag over the text SHALL NOT. A click on a hunk header SHALL still select
every changed line in that hunk.

The gesture over the text is needed for text, and there is one gesture. The
numbers are where a forge puts line selection, so it is where a hand already
reaches; and the hunk header, which is how most staging is actually done, does
not move at all.

What is *offered* over a line selection does not change: *Stage*, *Unstage*,
*Discard Selected Lines* and *Comment on Lines* appear and are hidden exactly
where `version-control` and `pull-requests` already say they do.

#### Scenario: dragging the numbers stages

- **GIVEN** an unstaged diff in the changes pane
- **WHEN** the pointer drags down the number column from line 12 to line 14
- **THEN** those lines are selected as lines, and the menu offers *Stage
  Selected Lines*

#### Scenario: dragging the text does not

- **GIVEN** the same diff
- **WHEN** the pointer drags over the text of lines 12 to 14
- **THEN** the selected text is what the drag covered, and no line is selected
  as a line

#### Scenario: the hunk header is unchanged

- **WHEN** a hunk header is clicked
- **THEN** every changed line in that hunk is selected as lines, as before

#### Scenario: a remark still names its lines

- **GIVEN** a pull request's diff
- **WHEN** lines 36 to 40 are selected in the number column and the menu is opened
- **THEN** it offers *Comment on Lines 36–40…*

### Requirement: The highlight covers the characters and nothing else

A text selection SHALL be drawn behind the glyphs it covers, ending where the
covered text ends rather than at the edge of the view, in the same colour a
selection is drawn in the editor — and in the unfocused colour while the
keyboard is somewhere else.

A highlight that runs to the margin makes a solid block with the text somewhere
inside it, so what is selected has to be worked out rather than seen; and a
selection drawn in the strong colour while the keyboard is in the file list says
the diff has the keyboard when it does not.

#### Scenario: the last row of a selection

- **GIVEN** a selection ending at the eighth character of a row
- **THEN** the highlight on that row is eight characters wide

#### Scenario: a whole row inside a selection

- **GIVEN** a selection running through a row whose text is twenty characters
- **THEN** the highlight on that row stops after those twenty characters, with a
  narrow mark for the line break

#### Scenario: the keyboard elsewhere

- **GIVEN** a text selection in a diff
- **WHEN** the keyboard moves to the file list beside it
- **THEN** the selection is still drawn, in the unfocused colour

### Requirement: A text selection belongs to one side of a side-by-side diff

Side by side, a text selection SHALL cover only the side the press landed on,
whatever the pointer does after it.

A selection covering both halves would copy two versions of a file interleaved
row by row, which is not something anybody means to select — and it is not
representable as text at all.

#### Scenario: dragging across the divider

- **GIVEN** a side-by-side diff and a press on the right-hand side of row 4
- **WHEN** the pointer is dragged past the divider and down to row 9
- **THEN** the selection covers the right-hand side of rows 4 to 9, and nothing
  on the left

#### Scenario: the left side selects too

- **GIVEN** a press on the left-hand side
- **WHEN** the drag runs down three rows
- **THEN** the selection is the old file's text on those rows

### Requirement: ⌘A, double-click and triple-click select what they do elsewhere

⌘A SHALL select all of the diff's text; a double-click SHALL select the word
under the pointer; a triple-click SHALL select the whole of that row's text.

A reader who has just discovered the drag works tries all three within the
minute, and each is what the same gesture means in the editor and the terminal.

#### Scenario: select all

- **GIVEN** a diff of forty rows
- **WHEN** ⌘A is pressed with the keyboard in the diff
- **THEN** every row's text is selected, and ⌘C copies the diff as text — one
  line per row, no markers, no numbers

#### Scenario: a word

- **WHEN** the pointer double-clicks the middle of `contentsOf`
- **THEN** `contentsOf` is selected

#### Scenario: a row

- **WHEN** the pointer triple-clicks a row
- **THEN** that row's whole text is selected, and no other row's

### Requirement: A remark in a diff is text like any other row

The rows a review comment occupies SHALL take part in a text selection and be
copied as the text they show, without the ✍️ or 💬 that marks them.

Answering a reviewer means quoting them, and a conversation drawn into the diff
that cannot be quoted sends the reader back to the browser this page exists to
replace.

#### Scenario: copying what somebody wrote

- **GIVEN** a diff with a comment of two rows under line 40
- **WHEN** a selection covers both rows and is copied
- **THEN** the clipboard holds the comment's text, over two lines, with no
  marker

#### Scenario: selecting a remark does not select it as a remark

- **GIVEN** a drag over a comment's text
- **THEN** the text is selected, and the menu offered is the text menu rather
  than the one that edits or deletes the remark — which a click on it still
  gives
