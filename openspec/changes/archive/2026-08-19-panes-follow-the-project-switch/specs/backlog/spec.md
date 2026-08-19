## ADDED Requirements

### Requirement: The pane shows the project the window is showing

The backlog pane SHALL show the records of whichever project the window is on,
and SHALL follow a switch without being closed and reopened. It is one pane per
window, made once and kept; keeping it must not mean keeping the project it was
made for.

**Everything the pane worked out from the project SHALL be worked out again** —
whether there is a backlog, whether there is an `openspec/`, and therefore which
of the two is being shown and whether the switch between them is offered at all.
A project with only `openspec/`, arrived at while the backlog was showing, would
otherwise leave the pane on a record that is not there.

**The pane SHALL stop watching the project it left.** A watcher is started only
where there is none, so one kept across a switch is a pane woken by a folder it
no longer shows and never woken by the one it does — right when it is opened and
stale a moment later, which is harder to notice than being stale throughout.

The pane SHALL be re-pointed rather than rebuilt: its place in the tab strip is
an arrangement somebody made.

A window switched to a project with neither record SHALL say so, as it does when
such a project is opened directly.

#### Scenario: navigating to another repository

- **GIVEN** the backlog pane open on one project
- **WHEN** the window follows a terminal into another repository
- **THEN** the pane shows the second project's items, without being reopened

#### Scenario: a project that keeps its work only in openspec

- **GIVEN** the pane showing a backlog
- **WHEN** the window switches to a project with `openspec/` and no backlog
- **THEN** the pane shows the changes, and offers no switch to a record that is
  not there

#### Scenario: a file touched in the project that was left

- **GIVEN** a window switched from one project to another
- **WHEN** an item is moved in the **first** project's folder
- **THEN** the pane does not move

#### Scenario: a file touched in the project now showing

- **GIVEN** that same window
- **WHEN** an item is moved in the second project's folder
- **THEN** the card moves, without the pane being clicked

#### Scenario: a project with neither record

- **WHEN** the window switches to a project with no backlog and no `openspec/`
- **THEN** the pane offers to make one, as it does when such a project is opened

#### Scenario: no pane open

- **GIVEN** a window with no backlog pane
- **WHEN** the project is switched
- **THEN** no backlog pane is opened

#### Scenario: entering a subproject

- **GIVEN** the pane open on a repository of several subprojects
- **WHEN** one of them is entered
- **THEN** the pane still shows the repository's records, because that is where
  they are
