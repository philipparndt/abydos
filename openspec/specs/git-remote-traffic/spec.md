# Git remote traffic

## Purpose

Fetch, pull, the pull dialog, and where its defaults come from — the app's own setting, or the repository's own config when it has one.

## Requirements

### Requirement: Work can be brought down as well as sent

The app SHALL be able to fetch and to pull, from the control that says how far
ahead of and behind the remote this branch is.

The app has been able to push since it could talk to a remote at all, and has
never been able to bring anything down. The counter in the git header reads what
it reads — `↓3 ↑1` — and is the button: fetch when level, pull when behind, push
when ahead.

#### Scenario: behind the remote

- **GIVEN** a branch three commits behind its upstream
- **WHEN** the counter is pressed
- **THEN** the pull dialog opens

#### Scenario: level with the remote

- **GIVEN** a branch level with its upstream
- **WHEN** the counter is pressed
- **THEN** a fetch runs and the counter is re-read

### Requirement: A pull says what it will do before it does it

The pull dialog SHALL name the remote, the branch to take from, the branch it
goes into, and SHALL offer to rebase instead of merging and to stash local
changes and put them back.

Remote and branch are pickers rather than assumptions: a pull from
`upstream/main` into a fork is exactly the case that otherwise needs a terminal.
The branch it goes into is stated and not editable — a pull goes into the branch
the work tree is on, and saying which one is the difference between a dialog that
can be read and one that has to be trusted.

The two options are `--rebase` and `--autostash`. What the dialog adds is that
the difference between a merge commit and a rewrite is said in words beside the
choice, once, at the moment it matters.

#### Scenario: a dirty working copy

- **GIVEN** three changed files and a pull to be made
- **WHEN** the dialog opens
- **THEN** it offers to stash them and put them back, and says how many there are

#### Scenario: pulling with rebase

- **GIVEN** one local commit not on the remote
- **WHEN** rebase is chosen
- **THEN** the dialog says the commit will be replayed and names the backup ref
  it will be kept at

### Requirement: The repository outranks the app about how it pulls

When the repository's own configuration sets `pull.rebase`, the dialog SHALL open
on what it says and SHALL say that this is where the setting came from.

A project that has decided how it pulls should not be quietly overridden by
somebody's preference in another program. The app-wide default fills the gap when
the repository is silent, which is most of the time.

#### Scenario: the repository has decided

- **GIVEN** a repository with `pull.rebase=false` and an app default of rebase
- **WHEN** the pull dialog opens
- **THEN** rebase is unticked and the dialog says the repository set it

#### Scenario: the repository is silent

- **GIVEN** a repository with no `pull.rebase`, and an app default of rebase
- **WHEN** the pull dialog opens
- **THEN** rebase is ticked

### Requirement: A refusal that needs a credential is reported as one

A fetch or pull that fails because git wanted a credential SHALL say so.

`GitPush` and `GitTags.push` set `GIT_TERMINAL_PROMPT=0` and point askpass at
`/usr/bin/false`, which is right — nothing should hang on a prompt nobody can
see. It also means a credential failure returns an exit code and no explanation,
and silence would make pull look broken rather than unauthenticated.

#### Scenario: no credential available

- **GIVEN** a remote needing a credential that is not configured
- **WHEN** a pull is run
- **THEN** the failure says a credential was wanted, rather than reporting nothing
