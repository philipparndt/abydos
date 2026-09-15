# replace-in-project Specification

## Purpose
TBD - created by archiving change the-project-search-replaces-what-it-found. Update Purpose after archive.
## Requirements
### Requirement: The search pane has a replace half, and ⇧⌘R is how

The search pane SHALL have a replace half — a field for what the matches should
become, a **Replace** for the rows that are selected and a **Replace All** for
every row the list is showing — shown while the pane is in replace mode and
hidden while it is not, with a `⇄` toggle in the option row to show and hide it.

⇧⌘R (*Replace in Project…*) SHALL make the pane if needed, seed the query from
the selection the way ⇧⌘F does when the pane was not up, turn replace mode on
and put the keyboard in the replacement field. ⇧⌘F SHALL focus the query and
SHALL NOT take replace mode away. The mode and the replacement text SHALL be the
pane's and SHALL survive a project switch, as the query does.

The usages pane SHALL NOT offer a replace half.

#### Scenario: ⇧⌘R with no pane up

- **GIVEN** a window with no search pane showing and `needle` selected in the
  editor
- **WHEN** ⇧⌘R is pressed
- **THEN** the pane appears with `needle` in the query, the replace half
  showing, and the keyboard in the replacement field

#### Scenario: ⇧⌘F while replacing

- **GIVEN** the pane in replace mode with a replacement typed
- **WHEN** ⇧⌘F is pressed
- **THEN** the keyboard goes to the query field, and the replace half and what
  is typed in it are still there

#### Scenario: the usages list

- **GIVEN** a usages list showing
- **WHEN** ⇧⌘R is pressed
- **THEN** the search pane is what gains a replace half, and the usages list
  is unchanged

### Requirement: Replace acts on the selected rows and Replace All on every row showing

**Replace** SHALL replace the selected rows: a selected match is replaced, and
a selected file heading brings every match in that file with it, folded open or
not. **Replace All** SHALL replace every row the list is showing, and SHALL
leave rows the hide-done toggle is hiding untouched. ⏎ in the replacement field
SHALL be Replace.

Replace SHALL be disabled while nothing is selected. Replace All SHALL be
disabled while the list is empty.

Marks SHALL NOT be changed by a replacement or its undo.

#### Scenario: two of three

- **GIVEN** a search with three matches in `a.swift`
- **WHEN** two of them are selected and Replace is pressed
- **THEN** those two are replaced in the file, the third is not, and the
  re-run list holds the third

#### Scenario: a heading

- **GIVEN** the heading for `a.swift` selected, the file folded shut
- **WHEN** Replace is pressed
- **THEN** every match in `a.swift` is replaced and no other file is touched

#### Scenario: hidden rows

- **GIVEN** ten matches, four of them marked done, the `✓` toggle hiding them
- **WHEN** Replace All is pressed
- **THEN** six are replaced and the four done rows still hold their text

#### Scenario: nothing selected

- **GIVEN** the pane in replace mode with rows but no selection
- **THEN** Replace is disabled and ⏎ in the replacement field does nothing

### Requirement: A replacement is made against the file as it is now

A replacement SHALL be made against the file's current text, never at the
offsets the list holds: each file's matches SHALL be found again in its current
text and the rows chosen SHALL be identified by their mark — path, matched line
text and occurrence — so a match that has moved is still replaced and a match
that is gone is not.

A file open in a tab, in any pane, dirty or clean, SHALL be edited through its
document as one edit, so the tab is marked dirty and one ⌘Z in that tab takes
the file's replacements back. A file that is not open SHALL be read again,
refused if it is binary or not UTF-8, edited as one span from the first replaced
match to the last with everything between them byte-for-byte what it was, and
written atomically. A read-only document SHALL be skipped and counted. A file
edited through its document SHALL be written when the auto-save setting is on,
so that the search run again afterwards reads what the editor holds.

#### Scenario: a dirty tab

- **GIVEN** `a.swift` open with an unsaved line typed above its matches
- **WHEN** Replace All is pressed
- **THEN** the matches are replaced where they now are, the unsaved line is
  kept, the tab takes the edit as its own — dirty until the auto-save writes
  it, where that setting is on — and one ⌘Z in the tab puts the matches back

#### Scenario: a file changed on disk since the search

- **GIVEN** a row for line 6 of `b.txt`, and `b.txt` rewritten by another
  program so that the matched line is gone
- **WHEN** Replace is pressed on that row
- **THEN** nothing is written to `b.txt`, and the status line counts one not
  found

#### Scenario: a closed file

- **GIVEN** a file with matches on its first and last lines, not open in any tab
- **WHEN** Replace All is pressed
- **THEN** both are replaced on disk, the text between them is unchanged, and
  the file's line endings are as they were

### Requirement: A replacement means what the switches say it means

With the regular-expression switch off the replacement SHALL be literal, `$1`
included. With it on the replacement SHALL be a template in the dialect the
pattern is searched with — `$0` the whole match, `$1` the first capture. A
template naming a capture the pattern does not have SHALL disable Replace and
Replace All, SHALL be reported as `Replacement cannot be used` in the status
line, and nothing SHALL be written.

#### Scenario: a capture across files

- **GIVEN** the switch on, a pattern of `(\w+)_id` and a replacement of `$1Id`
  with matches in three files
- **WHEN** Replace All is pressed
- **THEN** every `user_id` in the three files is `userId`

#### Scenario: a group that does not exist

- **GIVEN** the switch on, a pattern with two captures and a replacement of `$7`
- **THEN** both buttons are disabled, the status line says the replacement
  cannot be used, and no file is changed

### Requirement: One ⌘Z in the list takes the whole replacement back

A replacement SHALL be one entry in the list's own undo, files written to disk
included. Undoing it SHALL put each file's span back to its text before the
replacement — through the document if the file is open, to disk if not — only
where the span still reads what the replacement left; a file changed since
SHALL be left as it is and the status line SHALL say how many were. Redo SHALL
put the replacement back under the same rule.

#### Scenario: undo across files

- **GIVEN** a Replace All that wrote to three closed files and one open tab
- **WHEN** ⌘Z is pressed in the list
- **THEN** all four hold their text from before, and the open tab shows it

#### Scenario: a file edited after the replacement

- **GIVEN** the same, and one of the closed files edited by hand afterwards
- **WHEN** ⌘Z is pressed in the list
- **THEN** the other three are put back, that one is left alone, and the
  status line says one was not put back

### Requirement: A list that is not the whole answer is not replaced all at once

Replace All SHALL be disabled while the list is a prefix of what is there —
when the walk stopped at a bound and the status line reads `more not shown` —
and the status line SHALL say the query is too broad to replace all at once.
Replace on a selection SHALL still work.

#### Scenario: a capped list

- **GIVEN** a query with more matches than the list will hold
- **WHEN** replace mode is on
- **THEN** Replace All is disabled, and selecting two rows and pressing Replace
  replaces those two

### Requirement: The status line leads with what was replaced

After a replacement the status line SHALL lead with the number replaced and
the number of files — `143 replaced in 27 files` — followed by `· N not found`
when chosen rows were not found in their files, and the search SHALL be run
again so that replaced rows leave the list, with what the re-run finds
following in the same line. A replacement that still matches the query brings
its row back, and the leading number is what says the replacement happened.

#### Scenario: after Replace All

- **GIVEN** 143 matches in 27 files, all replaced
- **WHEN** the re-run finishes
- **THEN** the status line reads `143 replaced in 27 files · No results`

#### Scenario: a replacement that matches its own query

- **GIVEN** a query of `foo` and a replacement of `foobar` over five matches
- **WHEN** Replace All is pressed and the re-run finishes
- **THEN** the status line reads `5 replaced in 1 file · 5 in 1 file`, and the
  files hold `foobar`

