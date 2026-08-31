# Git pages — delta

## ADDED Requirements

### Requirement: A ref-scoped log includes what the upstream has

A log page scoped to a ref that has an upstream SHALL list the union of the
ref's ancestry and the upstream's, so the commits the branch is behind by are
on the page. A ref with no upstream, and the unscoped log, are unchanged. The
page shows what the last fetch brought and fetches nothing itself.

A repository saying "1 behind" in its header while "Log · main" shows no trace
of that commit is a log telling somebody deciding whether to pull that there
is nothing to pull.

#### Scenario: a branch behind its upstream

- **GIVEN** `main` whose upstream `origin/main` has one commit `main` does not
- **WHEN** the log is opened scoped to `main`
- **THEN** that commit is on the page

#### Scenario: a branch with no upstream

- **GIVEN** a branch that has never been published
- **WHEN** the log is opened scoped to it
- **THEN** the page lists that branch's ancestry, as it does today

#### Scenario: diverged histories are both told

- **GIVEN** `main` two ahead of and one behind `origin/main`
- **WHEN** the log is opened scoped to `main`
- **THEN** the two unpushed commits and the one unpulled commit are all on the
  page

### Requirement: Remote-only rows are dimmed, their chip is not

A commit the upstream has and the scoped ref does not SHALL be rendered
dimmed — the row's own colours at a quieter alpha, the way a merged branch is
dimmed in the refs tree — and the ref chip that explains the row (its
`origin/…` name) SHALL keep full strength. Where the graph is drawn, the
remote-only rows' lane strokes and dots dim with them.

#### Scenario: the unpulled commit reads quieter

- **GIVEN** a scoped log holding one remote-only commit
- **WHEN** the page is drawn
- **THEN** that row's subject, meta and graph are dimmed and the rows of the
  branch's own commits are not

#### Scenario: the chip stays legible

- **GIVEN** the remote-only row at the upstream's tip
- **WHEN** the page is drawn
- **THEN** its `origin/…` chip is drawn at full strength

#### Scenario: a dimmed row is still a commit

- **WHEN** a remote-only row is selected
- **THEN** it opens like any other commit — its files and its diff

### Requirement: The graph places remote commits by their parentage

Remote-only commits SHALL be laid out by the same lane algorithm as every
other commit: on the branch's own lane when the upstream is a fast-forward
ahead, and on a lane of their own from the point where the histories
diverged. The graph invents no dedicated remote lane; where the commits sit
is decided by the changesets they are built on.

#### Scenario: a fast-forward ahead shares the lane

- **GIVEN** `origin/main` strictly ahead of `main`
- **WHEN** the scoped log is drawn
- **THEN** the unpulled commits sit above `main`'s tip on the same lane

#### Scenario: a divergence opens a lane

- **GIVEN** `main` and `origin/main` each with commits of their own since
  their common ancestor
- **WHEN** the scoped log is drawn
- **THEN** the remote-only commits occupy a second lane that joins the
  branch's lane at the common ancestor

### Requirement: Paging a scoped log keeps its scope

Loading more of a ref-scoped log SHALL page the same scoped question —
the ref and its upstream — not fall back to the log of everything.

#### Scenario: the second page is the same log

- **GIVEN** a log scoped to `main` whose first page is full
- **WHEN** more commits are loaded
- **THEN** the added rows continue `main` and `origin/main`'s ancestry and
  commits reachable only from other branches do not appear
