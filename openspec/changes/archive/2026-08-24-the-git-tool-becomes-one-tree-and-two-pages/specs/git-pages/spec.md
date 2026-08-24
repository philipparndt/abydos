## ADDED Requirements

### Requirement: The log is a page in the editor area

The log SHALL open as a page in the editor area, not as a pane in the sidebar.

A graph needs width for its lanes and its refs, and a commit needs its files and
diff beside it rather than beneath it; a 300 pt column gives neither. The editor
area already takes git's detail — `openDiff` and `openCommitDiff` are wired up
and used — so this finishes a journey the panes started.

`LaunchConfigurationsPage` is the precedent: a non-file page that can be left
open, switched away from, and come back to.

#### Scenario: opening the log

- **GIVEN** a branch selected in the refs tree
- **WHEN** the log is opened
- **THEN** it is an editor tab showing the graph, its refs, and the selected
  commit's files and diff beside it

### Requirement: The commit view is the same page in another tense

Composing a commit SHALL use the same page as the log, pointed at what is staged.

Both are a list of changes on the left, the diff of the selected one on the
right, and what to do with the set along the bottom. The working copy is the
commit that has not happened yet, which is why it sits in the refs tree above the
stashes and branches as a thing of the same kind.

The two lists — staged and unstaged — are kept, for the reason `ChangesPane`
already gives: a file can be in both at once, and one list with a tick per row
cannot show that.

#### Scenario: opening the commit page

- **GIVEN** three changed files, one of them staged
- **WHEN** the commit page is opened
- **THEN** staged and unstaged are separate lists
- **AND** selecting a file shows its diff beside them

### Requirement: A one-line commit does not need the page

The sidebar SHALL keep a single-line summary field and a commit button, and the
control that opens the page SHALL carry whatever has been typed into it.

The commit that needs no thought is the common one, and a trip to a tab for it
would be worse than the cramped message box this change removes. The field is the
page's subject line shown early, not a second way to commit.

#### Scenario: promoting a message to the page

- **GIVEN** a summary typed into the sidebar field
- **WHEN** the page is opened from beside it
- **THEN** the page's summary field holds what was typed

### Requirement: A commit is an object with verbs

A commit row SHALL offer checkout, branch from here, tag here, move a tag here,
revert, cherry-pick, reset to here, and comparison with the working copy.

The history pane offered two items, `Copy Commit Hash` and `Copy Subject`,
because verbs were filed wherever their object happened to be listed. Those that
can lose work go through the safety net.

#### Scenario: tagging a commit

- **GIVEN** a commit in the log
- **WHEN** tag-here is chosen and a name given
- **THEN** a tag is created at that commit and appears in the refs tree
