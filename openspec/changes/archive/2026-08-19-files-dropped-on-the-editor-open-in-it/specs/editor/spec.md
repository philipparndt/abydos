## ADDED Requirements

### Requirement: A file dropped on an editor group opens in it

A file dragged onto an editor group SHALL open in that group, in a tab, exactly
as opening it any other way does — dragged from the Finder, from another
application, or from the project tree.

The whole group SHALL be the target, not only the tab strip: the text is where
somebody is looking when they decide to drop something, and the group is already
the drop target for a tab being dragged between panes.

**Only file URLs SHALL be accepted.** A drag carrying a web address or anything
else SHALL be declined so it springs back, rather than opening a tab named after
something that is not a file.

**The operation offered SHALL be one the drag permits.** An external file drag
offers copy; answering with move is a drop that silently does nothing and is
indistinguishable from not accepting the drag at all.

Several files SHALL open several tabs, in the order they were dropped, with the
last in front, and none of them provisional — a preview tab is the answer to a
single click, and a drag is deliberate.

#### Scenario: a file from the Finder

- **GIVEN** a window open on a project
- **WHEN** a file is dragged from the Finder onto the editor
- **THEN** it opens in a tab in that group

#### Scenario: a file from outside the project

- **WHEN** a file that lies outside the project is dropped
- **THEN** it opens and is readable, as it does when opened from a terminal

#### Scenario: several at once

- **WHEN** three files are dropped together
- **THEN** three tabs open, and the last is in front

#### Scenario: something that is not a file

- **WHEN** a web address is dragged onto the editor
- **THEN** nothing opens and the drag springs back

#### Scenario: a tab is still a tab

- **GIVEN** a tab dragged from another group
- **WHEN** it is dropped on a zone of this group
- **THEN** it splits the group as it does today

### Requirement: Dropping a file does not change the window's project

A dropped file SHALL open in the window it was dropped on, and that window's
project SHALL NOT change because of it. The tree, the git state, the run
configurations, the language servers and the remembered session all belong to the
project; re-pointing them is a large answer to a small gesture.

This is deliberately unlike a file dropped on the **Dock icon**, which is
addressed to the application rather than to a window and so has to find one, and
opens the project enclosing the file. A file dropped on a window is addressed to
that window.

#### Scenario: a file from another repository

- **GIVEN** a window open on one project
- **WHEN** a file belonging to a different checkout is dropped on the editor
- **THEN** it opens in a tab
- **AND** the window is still on the project it was on

#### Scenario: a file already inside the project

- **WHEN** a file from the open project is dropped
- **THEN** it opens, the same as double-clicking it in the tree

### Requirement: A dropped folder opens as a project

A folder dropped on an editor group SHALL be opened as a project, not as a set of
tabs and not refused. A folder means a project everywhere else here — `abydos
<dir>`, the Dock icon, the project switcher — and this SHALL add no further
variant: it goes through the same opening as those, so it honours the setting for
whether a project takes this window or a new one, and raises the existing window
where that project is already open.

A drag holding both files and folders SHALL open the folders first and then the
files, **into the window the folder opened**. The other order loses the file: it
is opened into the project being left, and switching restores the arriving
project's session over the top of it — measured, and it discarded the file
entirely. With several folders the first takes the files, being the one the drop
was aimed at.

#### Scenario: a folder from the Finder

- **WHEN** a folder is dropped on the editor
- **THEN** it opens as a project, the way opening it from the switcher does

#### Scenario: a folder already open

- **GIVEN** a window already showing that project
- **WHEN** the folder is dropped
- **THEN** that window is raised rather than a second one appearing

#### Scenario: a folder and a file together

- **WHEN** both are dropped in one drag
- **THEN** the folder opens as a project
- **AND** the file is open in that project's window, not lost with the one that
  was left
