# selection-occurrences

## ADDED Requirements

### Requirement: A selection lights the other places its text appears

Selecting text in the editor SHALL highlight every other place in the same file
where those characters appear, without anything being opened, typed or pressed.

"Where else is this" is asked constantly while reading code, and the two answers
that exist both cost more than the question: ⌘F takes the keyboard, needs the
query seeded and throws its answer away on ⎋; Find in Project answers a broader
question as a list of rows at the bottom of the window.

The selection itself SHALL NOT be banded. What is selected is already said by the
selection, and a band over it would be a second claim covering a louder one.

#### Scenario: a name selected

- **GIVEN** a file where `count` appears four times
- **WHEN** one of them is selected
- **THEN** the other three are highlighted, and the selected one is drawn as a
  selection and nothing more

#### Scenario: nothing else to say

- **GIVEN** a selection whose text appears nowhere else in the file
- **THEN** nothing is highlighted, and nothing is reported

### Requirement: What is matched is exactly what was selected

The match SHALL be literal and case-sensitive: the characters selected, and no
others.

A selection is a run of characters rather than a symbol, so a match inside a
longer word is a match — selecting `count` lights the `count` in `accountId`.
That is the chosen behaviour and not a limitation: a rule that lit only whole
words would highlight nothing at all for `x + y` or `unt`, and a feature that
does nothing for half the selections somebody makes is one nobody relies on. What
a *symbol's* uses are is a different question with an answer of its own, Find
Usages, which reads the language server rather than the characters.

#### Scenario: inside a longer word

- **GIVEN** `let count = 0` and `let accountId = 7` in one file
- **WHEN** `count` is selected on the first line
- **THEN** the `count` inside `accountId` is highlighted

#### Scenario: a different case is a different string

- **GIVEN** `Count` and `count` both in the file
- **WHEN** `Count` is selected
- **THEN** `count` is not highlighted

### Requirement: A selection that would say nothing lights nothing

A selection SHALL be highlighted elsewhere only when it is at least two
characters long, holds no line break, and is not made only of whitespace.

One character would band every `e` on the page: a screen of noise carrying no
information, since the answer to "where else is `e`" is "everywhere". A selection
spanning lines is a block being moved rather than a thing being looked up. A run
of spaces is an indent, and every indent in the file lighting up is the same
noise as `e` with more of it.

#### Scenario: one character

- **WHEN** a single character is selected
- **THEN** nothing is highlighted

#### Scenario: a selection across lines

- **WHEN** a selection covering more than one line is made
- **THEN** nothing is highlighted

#### Scenario: an indent

- **WHEN** a run of spaces or tabs is selected
- **THEN** nothing is highlighted

### Requirement: The bands are quieter than a find match, and behind the selection

The highlights SHALL be drawn in a colour of the scheme's own, quieter than a
find match, and at the depth the non-current find matches are drawn at — over the
line background and under the selection.

A find match is the answer to a question somebody asked; this is information
nobody asked for, and the two must not look alike.

The colour SHALL be one a scheme may leave out, with a stated derivation from
colours it already has. Schemes are files people keep in dotfiles repositories,
and a colour that arrived later must not refuse a file written before it existed.

#### Scenario: a scheme that says nothing about it

- **GIVEN** a scheme file written before this colour existed
- **WHEN** it is loaded
- **THEN** it loads, and the bands are drawn in a colour derived from ones the
  file does set

#### Scenario: over a selection

- **GIVEN** a selection extended over a place its own text appears again
- **THEN** the selection is what is drawn there, at full strength

### Requirement: Find's matches win while find is showing

While the editor is holding find matches, no occurrence highlights SHALL be drawn
and none SHALL be looked for.

Two kinds of band on one page meaning two different things is worse than one kind
meaning one thing, and the one somebody asked for is find's.

#### Scenario: find is open with matches

- **GIVEN** the find bar showing with matches highlighted
- **WHEN** text is selected in the code
- **THEN** the find matches are what is drawn, and no occurrence bands appear

#### Scenario: find is closed again

- **GIVEN** a selection standing after the find bar is closed
- **THEN** the occurrences of the selection are highlighted

### Requirement: The highlights are taken away the moment they stop being true

The bands SHALL be dropped as soon as the selection changes and as soon as the
text under them changes, before whatever replaces them is known.

Unlike the find matches, there is nothing here to carry across a change: the
selection *is* the query, so when it changes every band is about a question
nobody is asking any more. Bands left over text that no longer matches is the
fault `find-and-replace` was written to fix, and this must not bring it back by
another door.

The scan SHALL be debounced, so that dragging a selection across a paragraph
costs one scan and not one for every position the pointer passed through.

#### Scenario: the selection moves

- **WHEN** the selection changes to something else
- **THEN** the previous bands are gone at once, and the new ones appear when the
  scan has run

#### Scenario: dragging

- **WHEN** a selection is dragged across a paragraph
- **THEN** the file is scanned once, when the drag settles

#### Scenario: the text changes under a standing selection

- **GIVEN** a selection with its occurrences highlighted
- **WHEN** the file is rewritten by something else
- **THEN** no band is left at an offset the old text had
