# Version control — delta

## ADDED Requirements

### Requirement: Staging answers the click at once

Staging or unstaging SHALL move the affected rows to their new side as soon
as the git command reports success, with the following status re-read
confirming or correcting; the rows SHALL NOT wait for the full refresh. A
stage that took seconds to show left somebody double-clicking again to be
sure the first one registered.

#### Scenario: a staged file switches sides in one step

- **GIVEN** an unstaged file double-clicked to stage
- **WHEN** `git add` returns success
- **THEN** the row is on the staged side before any status re-read completes

#### Scenario: the status remains the authority

- **GIVEN** a stage whose command succeeded for some paths and not others
- **WHEN** the following status read lands
- **THEN** the trees show what the status says, whatever moved optimistically

### Requirement: A refresh that arrives busy is kept

A refresh requested while the pane is mid-operation SHALL run after the
operation instead of being dropped. Dropping it meant a second double-click
during a stage vanished, and the trees waited for an unrelated event to
come true again.

#### Scenario: a change lands during a stage

- **GIVEN** a stage in flight
- **WHEN** a refresh is requested before it finishes
- **THEN** the trees re-read once the stage completes, without waiting for
  another event

### Requirement: The app's own writes do not re-walk the ignored files

The ignored-files walk — the expensive read over the whole work tree — SHALL
run when the ignore rules changed, and SHALL NOT be re-triggered by the
app's own index writes. Every stage was paying 0.8–1.6 s for it because the
repository object was rebuilt on each `.git` event, discarding the
fingerprint that existed to prevent exactly this.

#### Scenario: staging does not pay the walk

- **GIVEN** a repository with a large ignored build directory
- **WHEN** a file is staged and the watcher reports the index write
- **THEN** no ignored-files walk runs

#### Scenario: an edited ignore file still does

- **WHEN** a `.gitignore` is saved
- **THEN** the walk runs and the tree's ignored markings update

### Requirement: The diff render does not stand in front of the stage

The diff shown for a selected row SHALL NOT delay an immediately following
stage: the render is deferred past the double-click interval and cancelled
by the activation, so the second click of a double-click is not queued
behind a parse of a diff nobody kept.

#### Scenario: a double-click stages without rendering the diff first

- **GIVEN** a large changed file
- **WHEN** it is double-clicked to stage
- **THEN** the stage runs without a diff render preceding it

#### Scenario: a single click still shows the diff

- **WHEN** a row is clicked once
- **THEN** its diff appears after the deferral, as before
