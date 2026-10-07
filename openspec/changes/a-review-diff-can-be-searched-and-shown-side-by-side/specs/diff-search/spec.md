## Purpose

Finding text in a diff the way a file is searched: what in a diff counts as a
match, how the matches are marked and walked, and how a search survives the
diff under it being rebuilt — by another file, the whole-file switch, or the
switch between unified and side by side.

## ADDED Requirements

### Requirement: A diff is searched with the editor's find bar

A diff that offers search SHALL be searched through the same find bar the editor
uses — the same field, the same match case, whole word and regular expression
switches, the same `n of m` — opened by ⌘F, stepped by ⌘G and ⇧⌘G and by Return
and ⇧Return in the field, and closed by ⎋. The bar SHALL be find-only: a diff of
somebody else's change has nothing to replace, and a replace row whose buttons
cannot fire is worse than none.

Opened over a text selection in the diff, the bar SHALL be seeded with the
selected text, as it is in a file.

#### Scenario: opening it

- **GIVEN** a diff that offers search, with nothing selected
- **WHEN** ⌘F is pressed
- **THEN** the find bar appears above the diff, its field has the keyboard, and
  no replace row is shown

#### Scenario: seeded from the selection

- **GIVEN** the word `checkout` selected in the diff
- **WHEN** ⌘F is pressed
- **THEN** the field reads `checkout` and its matches are marked

#### Scenario: closing it

- **GIVEN** the find bar open with matches marked
- **WHEN** ⎋ is pressed
- **THEN** the bar goes away, the marks go with it, and the diff has the keyboard

### Requirement: What a match is, in a diff

A search SHALL match the text of the code lines as the file holds them — without
the `+`, `-` or space git puts in front of each — on both sides of the change:
a removed line is searched as well as an added one. Hunk headers, the scope line
git guesses for a hunk, git's preamble and the remarks drawn under lines SHALL
NOT be searched.

Side by side, a line that is unchanged is drawn on both halves and SHALL count
as one match, not two, so that the count is the same in either arrangement.

A match SHALL NOT span two lines, as in a file searched line by line; the match
limit the editor keeps applies here too.

#### Scenario: a removed and an added line

- **GIVEN** a diff that removes `let count = 1` and adds `let count = 2`
- **WHEN** `count` is searched for
- **THEN** there are two matches, one on each line

#### Scenario: the prefix is not text

- **GIVEN** an added line `+value`
- **WHEN** `+value` is searched for
- **THEN** there are no matches, and searching for `value` finds the line

#### Scenario: an unchanged line side by side

- **GIVEN** a diff shown side by side, with `import AppKit` as unchanged context
- **WHEN** `import AppKit` is searched for
- **THEN** the bar reads `1 of 1`, and the match is marked on the right half

#### Scenario: a remark is not searched

- **GIVEN** a remark under line 40 that says `rename this`
- **WHEN** `rename this` is searched for, and no code line holds it
- **THEN** the bar says there are no matches

### Requirement: Matches are marked, and the current one is shown and selected

Every match in the diff SHALL be marked. One match SHALL be current: it is marked
distinctly from the rest, its row scrolled into view if it is not already
visible, and selected as text, so that ⌘C copies
it as `diff-selection` says. Stepping past the last match SHALL wrap to the
first, and before the first to the last, as in a file.

The first current match on opening the bar or changing the query SHALL be the
first match at or below the top of what is on screen, so that a search does not
throw the reader back to the start of a long diff.

#### Scenario: stepping

- **GIVEN** a diff with five matches, the bar reading `1 of 5`
- **WHEN** ⌘G is pressed twice
- **THEN** the bar reads `3 of 5`, the third match is in view and selected, and
  the other four are still marked

#### Scenario: wrapping

- **GIVEN** the bar reading `5 of 5`
- **WHEN** ⌘G is pressed
- **THEN** the bar reads `1 of 5` and the first match is in view

#### Scenario: starting where the reader is

- **GIVEN** a diff scrolled so that rows 300 to 340 are on screen, with matches
  at rows 10, 320 and 900
- **WHEN** the query is typed
- **THEN** the match at row 320 is current, and the diff does not scroll

### Requirement: A search survives the diff under it being rebuilt

While the bar is open, anything that rebuilds the diff — another file shown,
the whole-file switch, the switch between unified and side by side, the zoom —
SHALL run the same query with the same switches over what is now shown. Where
the match that was current still exists in the rebuilt diff, it SHALL stay
current; otherwise the rule for a first current match applies.

A diff with no textual changes, or a file shown as pictures, SHALL report no
matches rather than keep those of the file before it.

#### Scenario: another file

- **GIVEN** the bar open on `count`, with three matches in the file shown
- **WHEN** another file with one `count` in it is chosen
- **THEN** the bar reads `1 of 1` against the new file, and the query is still
  `count`

#### Scenario: switching arrangement

- **GIVEN** a unified diff with the bar reading `4 of 7`, that match on screen
- **WHEN** the diff is switched to side by side
- **THEN** the bar reads `4 of 7`, and that match is in view and selected on
  the half its line belongs to

#### Scenario: switching with the match scrolled away

- **GIVEN** the bar reading `4 of 7`, and the diff scrolled so that match is
  off screen
- **WHEN** the diff is switched to side by side
- **THEN** the bar reads `4 of 7`, and the diff stays where the reader had
  scrolled it rather than going back to the match

#### Scenario: a picture

- **GIVEN** the bar open with matches in a source file
- **WHEN** a changed PNG is chosen
- **THEN** the bar says there are no matches
