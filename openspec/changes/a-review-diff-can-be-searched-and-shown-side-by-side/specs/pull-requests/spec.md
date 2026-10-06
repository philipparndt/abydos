## ADDED Requirements

### Requirement: The diff on a pull request page can be searched

A pull request page SHALL offer search over the diff it is showing, as
`diff-search` says, opened by ⌘F whenever the keyboard is anywhere on the page —
the file list as well as the diff. The search covers the file shown, not every
file the pull request changes: it is the question a reader asks of a file, and
walking the files with the bar open keeps the question.

⌘F on the page SHALL NOT fall through to an editor tab behind it, and SHALL NOT
do nothing.

#### Scenario: from the file list

- **GIVEN** a pull request page with the keyboard on its file list
- **WHEN** ⌘F is pressed
- **THEN** the find bar opens over the diff of the selected file

#### Scenario: walking the files with one question

- **GIVEN** the bar open on `retry`, and the file list with the keyboard
- **WHEN** the down arrow selects the next file
- **THEN** the bar shows that file's matches for `retry`

### Requirement: The page switches between unified and side-by-side diffs

A pull request page SHALL offer a *Side by side* switch among its controls,
beside *Whole file*. On, the diff shows the old file's lines on the left and the
new file's on the right, paired; off, it shows them in place, one column.

It SHALL be the same preference View ▸ Diff ▸ Side by Side Diff sets: flipping
either SHALL change both, and every diff in the window, because two answers to
whether a diff is side by side would leave the changes pane and the review
disagreeing about what a diff looks like. The menu's tick SHALL say what the
preference is now, whichever of the two set it last.

Remarks, writing a remark, the whole-file switch and ticking files SHALL behave
the same in either arrangement.

#### Scenario: turning it on

- **GIVEN** a pull request page showing a unified diff
- **WHEN** *Side by side* is switched on
- **THEN** the diff shows the old lines on the left and the new on the right,
  and View ▸ Diff ▸ Side by Side Diff is ticked

#### Scenario: the menu moves the switch

- **GIVEN** a pull request page with *Side by side* off
- **WHEN** View ▸ Diff ▸ Side by Side Diff is chosen
- **THEN** the diff is side by side and the page's switch reads on

#### Scenario: whole file, side by side

- **GIVEN** *Whole file* and *Side by side* both on
- **WHEN** a file is shown
- **THEN** the whole file is shown in pairs, with the changes paired where they
  occur

### Requirement: Switching the arrangement keeps the reader's place

Switching between unified and side by side SHALL keep the line that was at the
top of the diff at the top afterwards, or as near it as the new arrangement
allows. A reviewer half-way down a long file who switches to see a change in
pairs has not asked to start again.

#### Scenario: half-way down

- **GIVEN** a unified diff scrolled so that new-file line 480 is the top row
- **WHEN** *Side by side* is switched on
- **THEN** the top row of the side-by-side diff holds new-file line 480
