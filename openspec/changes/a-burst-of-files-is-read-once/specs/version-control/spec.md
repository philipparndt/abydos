# Version control

## ADDED Requirements

### Requirement: A burst of filesystem events is read once, and a single save at once

Work SHALL run at once for the first filesystem event after a quiet spell when
it costs a `git status` or more — the tree's colours, the Dependencies section,
the changes pane — and during a burst SHALL run once after it has been quiet
for 0.6 s, and at least every 3 s while it lasts. What
it runs on SHALL be every batch it stood in for, folded together. The tree's
rows SHALL keep following the disk as each batch arrives, and a refresh
somebody asked for SHALL NOT wait.

The changes pane SHALL read one estate at a time, folding what is asked for
meanwhile into one read after it.

#### Scenario: a single save

- **GIVEN** nothing has changed on disk for a second
- **WHEN** a file is saved
- **THEN** the changes pane and the tree's colours update as quickly as before

#### Scenario: a worktree added and removed in a loop

- **GIVEN** an open superproject with the changes pane up
- **WHEN** a worktree is added and removed repeatedly for 30 s
- **THEN** new and removed rows appear in the tree as they happen
- **AND** the colours and the changes list update at most every 3 s and once
  more after the loop ends
