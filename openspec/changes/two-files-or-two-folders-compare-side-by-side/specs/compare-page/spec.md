## ADDED Requirements

### Requirement: Any two files or any two folders open as one compare page

The app SHALL open a compare page — an editor tab — over any two sources of
the same kind, where a source is a file on disk, a folder on disk, a file at a
commit, or a folder at a commit.

A file and a folder SHALL NOT be compared with each other: the gesture that
would make them A and B is refused, with the reason in a tip.

The page is an editor tab like the diff tab and the log page: it splits, tears
off, and is remembered by `sessions` as those are. A remembered page whose side
no longer exists — a temporary directory git made for a `--dir-diff` — comes
back as a tab that says so rather than as an empty diff.

#### Scenario: two files on disk

- **WHEN** the page is opened over `~/a/Package.swift` and `~/b/Package.swift`
- **THEN** the tab shows the two files side by side as `file-diff` describes,
  titled `Package.swift | Package.swift`, with the counts under the title

#### Scenario: two folders on disk

- **WHEN** the page is opened over `~/dev/abydos` and a worktree of it under `.claude/worktrees/`
- **THEN** the tab shows the two trees aligned as `folder-diff` describes,
  titled `abydos | <worktree>`

#### Scenario: a file and a folder

- **WHEN** a folder is dropped onto a page whose A is a file, and the drop is
  marked B
- **THEN** the drop is refused and the tip says a file is compared with a file

#### Scenario: a side that was a temporary directory is gone

- **GIVEN** a remembered compare page over two directories git made for a
  `--dir-diff`
- **WHEN** the project is opened again and the directories no longer exist
- **THEN** the tab comes back saying which side is missing, and offers to close

### Requirement: The page is opened from the tree, by dropping, from the history and from the command line

The compare page SHALL be reachable in four ways: *Compare* over two selected
rows of the project tree; a file or folder dropped onto an open file of the
same kind; *Compare ▸ With…* on a file, which asks with an open panel; and
`abydos-diff A B` from a terminal, which also serves as a `git difftool`.

Inside one of the app's own terminals `abydos-diff` reaches the window the
pane belongs to, the way `abydos` does; elsewhere it goes through `open -a`.

#### Scenario: two rows in the project tree

- **GIVEN** two files selected in the project tree
- **WHEN** *Compare* is chosen from the context menu
- **THEN** a compare page opens with the first selected as A and the second as B

#### Scenario: a file dropped onto an open file

- **GIVEN** `main.go` open in the editor
- **WHEN** another file is dropped from the Finder onto its text
- **THEN** a compare page opens with the open file as A and the dropped file as B

#### Scenario: from a terminal

- **WHEN** `abydos-diff old.yaml new.yaml` is typed in one of the app's terminals
- **THEN** a compare page over the two files opens in that terminal's window

#### Scenario: as a git difftool over directories

- **GIVEN** `git config diff.tool abydos` pointing at `abydos-diff`
- **WHEN** `git difftool --dir-diff HEAD~3` is run
- **THEN** a compare page opens over the two directories git made, as a folder diff

### Requirement: The shelf shows a side over each half, and a swap between them

The page SHALL keep a shelf of every source it has been given and SHALL show,
across the top, the source that is A over the left half and the source that
is B over the right half, each with its letter, its name and where it is from
— a path, or a commit's short hash. Between the two, over the gutter, one
control SHALL swap the sides. Dropping a further file or folder onto the page
adds it to the shelf without changing the comparison; either side's card then
offers every source on the shelf as a menu, and choosing the other side's
source is the swap.

The first version put an A chip and a B chip on every card, and pressing A on
the B card left one card holding both: two letters on every card asked a
question the two halves below already answer.

#### Scenario: a third document is dropped

- **GIVEN** a page comparing draft 1 and draft 2 of a document
- **WHEN** draft 3 is dropped onto the page
- **THEN** the shelf holds three rows and the diff is still of 1 and 2

#### Scenario: the swap

- **GIVEN** a page comparing draft 1 as A and draft 2 as B
- **WHEN** the swap between the cards is pressed
- **THEN** draft 2 is A and draft 1 is B

#### Scenario: B is moved to the third

- **GIVEN** that shelf
- **WHEN** draft 3 is chosen from the B card's menu
- **THEN** the diff is of draft 1 and draft 3

#### Scenario: the other side's source is chosen

- **GIVEN** a page comparing draft 1 as A and draft 2 as B
- **WHEN** draft 2 is chosen from the A card's menu
- **THEN** draft 2 is A and draft 1 is B

### Requirement: The file's history is a rail beside the diff, and any commit can be a side

When A or B is a file in a git repository, the page SHALL show that file's
history down its edge — one row per commit that touched the path, with the
author, the short hash, the date and the subject — and each row SHALL carry the
same A and B chips as the shelf. Marking a chip compares that revision of the
file.

A row's hash opens the commit on the log page `git-pages` already has; the row
itself does not navigate, because a click on it is how a chip is reached.

#### Scenario: two revisions by clicking

- **GIVEN** a compare page over `README.md` on disk, with the rail showing its history
- **WHEN** the A chip on one commit and the B chip on a later one are clicked
- **THEN** the diff is of the file at the first against the file at the second,
  and the title carries both short hashes

#### Scenario: the previous commit

- **GIVEN** the rail with B on some commit
- **WHEN** the A chip on the row below it is clicked
- **THEN** the diff is that commit's change to this file

#### Scenario: a file outside any repository

- **WHEN** the page is opened over two files that are in no git repository
- **THEN** there is no rail, and the page says nothing about history

### Requirement: The title says what is compared and how much differs

The tab's title SHALL name both sides, `A | B`, and a line under it SHALL count
what differs: for a file diff, additions, deletions and changes; for a folder
diff, different, equal, unmatched and ignored, with *n still comparing* while
any row's answer is not yet in.

#### Scenario: a file diff

- **WHEN** the diff of two files has 4 added lines, 2 removed and 3 changes
- **THEN** the line under the title reads `4 Additions, 2 Deletions, 3 Changes`

#### Scenario: a folder diff still comparing

- **WHEN** a folder diff has listed its rows and 12 equal-sized pairs are not yet compared
- **THEN** the counts say how many are different, equal, unmatched and ignored so
  far, and `12 comparing…`
