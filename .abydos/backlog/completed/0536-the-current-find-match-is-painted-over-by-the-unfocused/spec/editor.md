<!-- What this item changes about `editor`. Folded into
     .abydos/backlog/spec/editor.md by `abydos-backlog done`.

     ADDED, MODIFIED and REMOVED. A rename is a REMOVED and an ADDED.
     Write each requirement as it will read in the spec, in the present
     tense — not as a description of the edit.
     The requirements already there, to name exactly:
       ⌘/ comments out the lines a selection touches
       the comment goes at the indent the lines share
       blank lines are neither commented nor counted
       the selection still covers the same text afterwards
       a language with no line comment says so rather than nothing
       an embedded language gets its host's comment, not its own
       ⌘/ is ⌘/ on every keyboard
       ↑ on the first line and ↓ on the last go to the edge of the file
       Shift takes the selection to the edge with it
       ⌃B and ⌃F move the caret a character, and so do ← and →
       ⌃A and ⌃E go to the ends of the line, and so do ⌥↑ and ⌥↓
       ⌃K deletes to the end of the line and leaves the newline
       ⌃O opens a line under the caret and leaves the caret alone
       A selection is drawn gray while the keyboard is somewhere else
       A place the editor is sent to is on the screen when it gets there
-->

## ADDED Requirement: The current find match is the loudest thing on the page

Find in a file highlights every match on screen, and the one being looked at —
the one the counter says is 2 of 3, the one ⌘G moves — is drawn more strongly
than the rest. That is the whole reason there is a current match: a page of
identical bands answers "where are they" and not "where am I".

**It stays the loudest whatever else lands on the same characters.** Revealing a
match selects it, so the current match is also a selection, and a selection is
drawn over the line's background — which used to mean the strongest highlight in
the file was covered by one of the quietest colours in the scheme, and the match
somebody was reading became the darkest of the three on the screen. The current
match is therefore painted **after** the selection rather than before it. Which
of the two claims wins where they coincide is decided, rather than falling out of
the order two pieces of drawing code happen to run in.

Only the match's own rectangle is covered. A selection wider than the match — one
somebody extended, or a selection of whole lines — is still drawn in full, and
still reads as a selection either side of the match sitting on it.

This holds in both keyboard states. While a query is being typed the editor has
not got the keyboard and the selection is the scheme's quiet colour; with the
keyboard back in the code and ⌘G stepping on it is the strong one. Neither is
loud enough to matter, because neither is on top.

### Scenario: three matches on adjacent lines, the keyboard in the find field

- **Given** a file with three matches of the same word on consecutive lines
- **When** the find bar is open with that query and the first match is current
- **Then** the current match is drawn more strongly than the other two, which are
  drawn more strongly than the unhighlighted code

### Scenario: the keyboard back in the editor

- **Given** those three matches with the current one selected
- **When** the keyboard is in the editor and ⌘G steps to the second
- **Then** the second is now the strong one and the first has gone back to the
  quiet match colour

### Scenario: a selection wider than the match

- **Given** the current match on a line, and a selection of that line and the two
  below it
- **Then** all three lines are drawn as a selection, and the current match is
  drawn on top of its own characters within it

## ADDED Requirement: The find highlights are the scheme's colours

Both match colours belong to the scheme file — `searchMatchCurrentBackground` for
the one being looked at, `searchMatchBackground` for the rest — stated at both
lightnesses like every other colour a window is painted in. They were fixed in
the drawing code until this was written, chosen against one dark warm ground,
which is what every light scheme drew its find highlights in.

A scheme may leave either out, as it may leave `selectionBackgroundInactive` out
and for the same reason: they arrived after schemes were already files somebody
keeps. A file that says nothing gets a stated derivation rather than a silent
default — the current match halfway between `selectionBackground` and `caret`,
the other matches halfway again back towards `selectionBackground` — so a scheme
nobody has looked at cannot end up with the matches nobody is reading louder than
the one they are.

Every scheme the app ships states both. The rule they are judged against is that
the current match has more contrast against `editorBackground` than the other
matches *and* than either selection colour, since the current match is also the
selection and nothing that can land on the same characters may take the eye off
it.

### Scenario: a light scheme

- **Given** any of the shipped schemes at its light lightness
- **Then** its find highlights are its own colours, and the current match is the
  more contrasting of the two against its editor background

### Scenario: a scheme file that does not mention them

- **Given** a personal scheme written before these keys existed
- **Then** it loads, and its current match is halfway between its selection and
  its caret, with the other matches halfway between its selection and that
