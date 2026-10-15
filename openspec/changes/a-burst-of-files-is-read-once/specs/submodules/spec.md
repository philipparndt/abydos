# Submodules

## ADDED Requirements

### Requirement: A batch that could not name its files is read where it happened

The changes pane SHALL re-read, for a directory FSEvents says to scan instead
of naming the files under it, the repositories that directory touches and no
others: the submodule it lies in, or the superproject when it lies in none, and
every submodule beneath it at any depth. Only a scan of the project root SHALL
read the whole estate.

Before this the attribution was the wrong way round: every batch whose paths
were all named read the whole estate, and a batch that could not name them read
nothing.

#### Scenario: a worktree added beside the submodules

- **GIVEN** an open superproject whose submodules are under `repos/`
- **WHEN** a worktree of one of them is created at `repos/svc-3-wt-x`
- **THEN** the superproject is re-read and no submodule is

#### Scenario: a build inside one submodule

- **GIVEN** an open superproject of 200 submodules
- **WHEN** a build under `svc-47` produces a batch FSEvents cannot enumerate
- **THEN** `svc-47` is re-read and no other repository is

#### Scenario: the project root itself

- **WHEN** the batch is a scan of the project root, or the root moved
- **THEN** the inventory and every repository are read again
