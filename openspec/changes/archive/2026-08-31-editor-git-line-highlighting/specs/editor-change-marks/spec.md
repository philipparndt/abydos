# Editor change marks

## ADDED Requirements

### Requirement: Lines that differ from HEAD are marked in the gutter

An open file inside a git repository SHALL mark, in the gutter, every line
that differs from the file's content at HEAD: a bar beside a line that was
added, a bar in a second colour beside a line that was modified, and a
boundary mark under the line after which lines were deleted. The difference
is taken against HEAD, so staged and unstaged edits mark alike — the question
the gutter answers is "what have I changed since the last commit", not "what
have I staged".

#### Scenario: a line edited since HEAD

- **GIVEN** a committed file open in the editor
- **WHEN** one line is changed and the file is saved
- **THEN** that line carries a modified mark, and no other line carries any

#### Scenario: lines added since HEAD

- **WHEN** three new lines are inserted and the file is saved
- **THEN** those three lines carry added marks

#### Scenario: lines deleted since HEAD

- **WHEN** two adjacent lines are removed and the file is saved
- **THEN** a deletion mark sits under the line that preceded them

#### Scenario: a staged edit marks the same as an unstaged one

- **GIVEN** a changed line staged with `git add`
- **WHEN** the file is viewed
- **THEN** the line is marked exactly as it was before staging

### Requirement: A paired removal and addition is one modification

A hunk in which a run of removed lines is immediately followed by a run of
added lines SHALL mark those added lines as modified, not added. Calling every
edit an addition would paint the whole gutter as new code the moment a line is
touched, which is not what anybody means by "changed".

#### Scenario: one line replaced by one line

- **GIVEN** a diff hunk removing one line and adding one in its place
- **WHEN** the marks are computed
- **THEN** the new line is marked modified

#### Scenario: one line replaced by three

- **GIVEN** a hunk removing one line and adding three in its place
- **WHEN** the marks are computed
- **THEN** all three are marked modified, and no deletion mark appears

#### Scenario: an addition with no paired removal

- **GIVEN** a hunk that only adds lines
- **WHEN** the marks are computed
- **THEN** those lines are marked added

### Requirement: Marks stay aligned while somebody types

Between saves, marks SHALL move with the lines they belong to: an edit that
inserts or removes lines shifts every mark below it, and the lines an edit
touches are marked modified at once. A mark pointing at the line below the one
it means is worse than no mark, and waiting for a save to show any feedback
makes the gutter feel dead.

#### Scenario: typing above a marked line

- **GIVEN** a modified mark on line 10
- **WHEN** two lines are inserted at line 3, before any save
- **THEN** the mark sits beside line 12

#### Scenario: editing an unmarked line

- **WHEN** a character is typed on a previously unmarked line
- **THEN** that line shows a modified mark before the file is saved

### Requirement: Marks are recomputed when the truth changes

The marks SHALL be recomputed from a fresh diff when the file is saved, when
it is reloaded after changing on disk, and when the repository changes
underneath it — a commit, a checkout, a stage from the sidebar. A commit must
take the marks away: after it, nothing differs from HEAD any more. The
repository-change recompute applies to open tabs only and is debounced, so a
checkout touching a hundred files does not launch a hundred diff processes.

#### Scenario: committing clears the marks

- **GIVEN** a file with marked lines
- **WHEN** those changes are committed
- **THEN** the open file shows no marks

#### Scenario: an external edit is picked up

- **GIVEN** the file changed on disk outside the app and the editor reloaded it
- **WHEN** the reload completes
- **THEN** the marks reflect the reloaded content against HEAD

### Requirement: Files git is not tracking show no marks

An untracked file, an ignored file, and a file outside any repository SHALL
show no change marks. A wholly-new file with every line marked added is a
gutter saying nothing, loudly.

#### Scenario: an untracked file

- **GIVEN** a file never added to git, open in the editor
- **WHEN** it is edited and saved
- **THEN** no line carries a mark

#### Scenario: a file outside a repository

- **GIVEN** a file opened from a directory that is not a git checkout
- **WHEN** it is viewed
- **THEN** no line carries a mark

### Requirement: Computing marks never runs per keystroke

The diff behind the marks SHALL run asynchronously off the main thread and
only on the named triggers — open, save, reload, repository change — never per
keystroke or per frame. A result that arrives for a tab that has closed, or
after a newer trigger has fired, SHALL be dropped rather than applied.

#### Scenario: a stale result arrives late

- **GIVEN** a diff was started and the file was saved again before it finished
- **WHEN** the older result arrives
- **THEN** it is discarded and the newer diff's result is shown
