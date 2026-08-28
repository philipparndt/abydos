# editor

## ADDED Requirements

### Requirement: The find highlights belong to the text as it is now

A tab's matches SHALL follow every edit to its document, from any source: typing,
a replacement, an undo, or the file being rewritten underneath by an agent or a
`git checkout`.

An edit SHALL move the matches that survive it, drop the ones it destroyed, and
the search SHALL be asked again — so that nothing wrong is ever drawn, and the
answer on screen a moment later is the true one.

**Nothing re-ran the search when the text changed.** `runFind` was called from the
find field, from a tab coming to the front and from ⌘G, and from no edit anywhere,
so the ranges in a tab's find state were UTF-16 offsets into the text as it had
been when the search ran. A file searched for a path and then edited to take that
path off eight of its ten lines drew bands of the old length at the old offsets,
sliding across the words: `delivery-mail.mp4` marked as a match for a string not
on that line at all.

Those ranges are not only drawn — they set the caret. Handing a range from text
that no longer exists to `setSearchMatches` is the fault the code already names in
`stepMatch`, "a document that never produced that range", arriving from the other
direction: the same file, a different moment.

#### Scenario: text is edited out from under a match

- **GIVEN** a file searched for a string, with ten matches highlighted
- **WHEN** eight of the lines are edited so they no longer hold it
- **THEN** two matches are highlighted, both on the lines that still hold the
  string, and the bar says `2`

#### Scenario: an edit makes a new match

- **GIVEN** a file searched for a string, with two matches
- **WHEN** the string is typed on a third line
- **THEN** three matches are highlighted and the bar says so

#### Scenario: an edit above the matches

- **GIVEN** matches further down a file
- **WHEN** a line is inserted above all of them
- **THEN** the bands are over the same text, on their new rows, without waiting
  for the search to be asked again

#### Scenario: stepping after typing

- **GIVEN** the find bar open, a match current, and a character typed in the code
- **WHEN** ⌘G is pressed
- **THEN** it steps to the match after the one that was current, rather than back
  to the top of the file

#### Scenario: the file is rewritten by something else

- **GIVEN** a file with matches highlighted
- **WHEN** the file is rewritten on disk and the editor reloads it
- **THEN** the matches are the new text's, and none of the old offsets are drawn
