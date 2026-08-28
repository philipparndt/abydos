# git-pages

## MODIFIED Requirements

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

## ADDED Requirements

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
