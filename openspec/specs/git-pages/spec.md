# Git pages

## Purpose

The log tense and the commit tense of one editor page — one class at two sizes, so the loader, the collapse rule, the graph and the menus cannot drift apart.

## Requirements

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

Both are a list of changes on the left and the diff of the selected one on the
right. What to do with the set — the summary, the description and the commit row
— sits along the bottom **of the diff**, inside the right-hand side of the split,
so that the file lists run the page's full height and the divider moves the
message with the diff it is about.

It used to span the whole width, under the lists as well, which cost the tree
height for a message that has nothing to do with it.

The working copy is the commit that has not happened yet, which is why it sits in
the refs tree above the stashes and branches as a thing of the same kind.

The two lists — staged and unstaged — are kept, for the reason `ChangesPane`
already gives: a file can be in both at once, and one list with a tick per row
cannot show that.

#### Scenario: opening the commit page

- **GIVEN** three changed files, one of them staged
- **WHEN** the commit page is opened
- **THEN** staged and unstaged are separate lists
- **AND** selecting a file shows its diff beside them

#### Scenario: where the message sits

- **GIVEN** the commit page open
- **THEN** the summary, the description and the commit row are under the diff
- **AND** the file lists reach the bottom of the page

#### Scenario: dragging the divider

- **WHEN** the divider between the lists and the diff is dragged
- **THEN** the message area is the width of the diff, and moves with it

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

### Requirement: The description is collapsed until it is asked for

The commit page's description SHALL start collapsed, behind a chevron beside the
summary, and SHALL keep whatever has been typed into it when it is collapsed
again.

The page spent a fixed 224 points on its message area at every height — a
26-point summary, a description pinned at 150, a commit row, two gaps and the
insets — so a short page showed four lines of diff under an empty box. The
description is empty most of the time: the sidebar keeps the one-line case, and
this page is reached because somebody wants the diff or a longer message. The
diff is the thing that is already there; the description is the thing that has
not been written yet.

The rule SHALL be the same at every height. A description that appeared and
disappeared as the page was resized would be a layout nobody can predict, and the
height at which it changed would be a number nobody knows.

The chevron's state SHALL be kept for as long as the page is open, so that
somebody who writes a description opens it once rather than once per commit; a
page opened afresh starts collapsed.

#### Scenario: a short page

- **GIVEN** the commit page in a pane a few hundred points tall
- **THEN** the description is collapsed, and the diff has the height the box
  would have taken

#### Scenario: opening it

- **WHEN** the chevron is pressed
- **THEN** the description appears, and the diff gives up the height

#### Scenario: what is typed survives being put away

- **GIVEN** a description somebody has typed
- **WHEN** it is collapsed and expanded again
- **THEN** the text is as it was

#### Scenario: the next commit

- **GIVEN** a description opened and a commit made
- **WHEN** the next message is written on the same page
- **THEN** the description is still open

### Requirement: The commit page does not take the window

Opening the commit page SHALL NOT maximise the editor.

It did, along with the log, because it was unreadable small — and it was
unreadable small for a reason this change removes rather than for what it holds:
a fixed 224 points of message area across the whole width, leaving four lines of
diff on a short page. With the message two rows tall and under the diff, the page
reads at the size it is given, and taking somebody's tree and terminal away to
show them a commit is a thing to do only when the page cannot be read otherwise.

The log page and the review page are unchanged: a graph, a list of commits and a
diff still want the room.

**The page therefore opens at whatever share the editor has**, and where the
terminal panel is holding most of the window that is a small page — measured on a
1200×560 window with the panel up: 120 points for the page and 56 for the diff.
That is chosen rather than overlooked. The panel's height is the person's own
arrangement, and rearranging it to show them a commit is the mode `giveTheEditor‑
TheWindow` already refuses to undo on the way out. Somebody who wants the room
has the same two gestures they always had: double-click the tab, or the View
menu.

#### Scenario: opening the commit page beside a tree

- **GIVEN** a window with the project tree showing
- **WHEN** the commit page is opened
- **THEN** the tree is still showing, and the page has the editor's share of the
  window

#### Scenario: the log still takes it

- **WHEN** the log page is opened
- **THEN** the editor takes the window, as it does today

### Requirement: Return at the end of the summary opens the description

Pressing Return in the summary field SHALL open the description and put the
keyboard in it.

It is what somebody does when they have finished the subject and mean to keep
writing.

Committing SHALL be ⌘Return. The button carried plain Return, so the page would
otherwise have no keyboard commit at all — and ⌘Return is what a page with a text
area on it means by "commit", working from the description as well, where Return
has always been a newline.

#### Scenario: pressing Return in the summary

- **GIVEN** a summary typed and the description collapsed
- **WHEN** Return is pressed
- **THEN** the description is open with the keyboard in it, and no commit is made

#### Scenario: committing

- **WHEN** ⌘Return is pressed, from the summary or from the description
- **THEN** the commit is made

#### Scenario: Return no longer commits

- **GIVEN** a summary typed
- **WHEN** Return is pressed
- **THEN** no commit is made
