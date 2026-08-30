# Git safety

## Purpose

What counts as destructive, what is asked before it runs, and the backup ref left behind so it can be undone. One place decides the list, so it stays closed rather than growing a case at a time.
## Requirements
### Requirement: An operation that can lose work says so and leaves a way back

An operation that could leave work unrecoverable SHALL say what it will cost
before it runs, and SHALL leave a ref behind from which it can be undone.

An operation is destructive when nothing left on this machine afterwards can put
it back. That set is small and closed: switching a branch over uncommitted work,
discarding, resetting to another commit, rebasing, amending, deleting a branch
that is ahead, and moving a tag.

**What is said SHALL lead with a number.** "4 commits leave main" is read; "this
cannot be undone" is not. The count is of the thing being lost — commits,
changed files — and the name of the backup ref is given with it.

#### Scenario: resetting to an earlier commit

- **GIVEN** a branch `main` with four commits after the one selected
- **WHEN** reset to that commit is chosen
- **THEN** the dialog says four commits leave `main` and names the backup ref
- **AND** nothing has happened until it is agreed

#### Scenario: staging is not destructive

- **GIVEN** a changed file
- **WHEN** it is staged
- **THEN** nothing is asked and no backup ref is made

### Requirement: A backup is a real branch under a folder of its own

A backup SHALL be a branch under `backup/`, named for the moment and the thing it
holds, and SHALL NOT be a private ref namespace or a tag.

The reflog is not enough: entries for unreachable commits expire after thirty
days by default and `gc` collects what they pointed at. A branch is reachable and
survives. A private namespace under `refs/abydos/` would be invisible to
`git branch`, to `git log --all`, and to anybody who has never heard of this app.
A tag would be pushed, and a private near-miss is not something to publish.

`backup/` folds to one row in the refs tree, so being visible costs no clutter.

#### Scenario: a branch is deleted while ahead

- **GIVEN** `feature/x`, three commits ahead of `main`
- **WHEN** it is deleted and the dialog agreed
- **THEN** a branch under `backup/` points at what `feature/x` pointed at
- **AND** `git branch` lists it

### Requirement: Uncommitted work is captured without disturbing it

Work that is not committed SHALL be captured with `git stash create`, which
writes a commit for the working copy without touching the working copy or the
stash list.

A backup that moved the files it was insuring would be a second surprise on top
of the first. `stash create` writes the commit and changes nothing; a branch
under `backup/` is then pointed at it.

#### Scenario: switching branches over uncommitted changes

- **GIVEN** three changed files and a checkout git refuses
- **WHEN** switch-and-leave-them is chosen
- **THEN** a backup ref holds the three files' state
- **AND** the working copy was not stashed or emptied before that ref existed

### Requirement: Only the choice that loses nothing may be remembered

A dialog SHALL offer to be remembered only when the option remembered is the one
that loses nothing.

`Always stash and switch` may be ticked, because a stash loses nothing.
`Always discard` may not be, ever. A dialog in front of a safe operation is what
teaches somebody to dismiss the one in front of an unsafe one, and a remembered
destructive answer is the same failure with the dialog removed.

#### Scenario: the switch dialog

- **GIVEN** the dialog offering to stash, or to switch and leave changes behind
- **THEN** the stash option carries a remember-this control
- **AND** the leave-them-behind option does not

### Requirement: Force-pushing a branch is refused rather than insured

Force-pushing a branch SHALL state how many commits on the remote would be
overwritten, and SHALL NOT claim a backup.

No local ref can recover somebody else's commits from a remote. Saying otherwise
would be the worst untruth this feature could tell. Moving a tag is the exception
and stays allowed: a moving tag is expected to be force-pushed, and what it left
is backed up locally because the old target is a local commit.

#### Scenario: the remote is ahead

- **GIVEN** `origin/main` holding two commits that are not local
- **WHEN** a force-push of `main` is asked for
- **THEN** it says two commits would be overwritten and no backup is claimed

### Requirement: What happened is said afterwards, with the ref named

After a destructive operation the app SHALL say what it did and name the backup
ref, with an undo offered.

Insurance nobody is told about is the same as none.

#### Scenario: after a reset

- **GIVEN** a reset that has run
- **THEN** a toast names the backup ref and offers to undo

### Requirement: An operation over many repositories is insured once and reported per repository

An operation that can lose work across an estate SHALL ask once for the whole
operation, back up every repository it will touch before touching any of them,
and report its outcome per repository.

Asking two hundred times is asking nobody: a dialogue repeated per repository is
answered by holding the return key, which is the safety net working exactly as
well as no safety net at all. So one question, naming how many repositories it
covers and what will happen in them.

The backups SHALL all be made first. A run that backs up and acts, repository by
repository, has no way back from a failure at repository 140 — the first 139 have
moved and only some of them were recorded. Backing up everything first means the
way back exists for the whole operation before any of it happens.

**A partial run SHALL be reported as partial**, naming which repositories were
changed and which were not, and the backup refs that lead back. `What happened is
said afterwards, with the ref named` is the existing rule; across an estate it is
one line per repository that changed, not one line for the operation.

#### Scenario: discarding across six submodules

- **GIVEN** changed files in six submodules selected for discard
- **WHEN** the discard is asked for
- **THEN** one question is asked, naming six repositories
- **AND** all six are backed up before any file is discarded
- **AND** what happened is said per repository, with each backup ref named

#### Scenario: a run that fails part way

- **GIVEN** the same six, where the fourth refuses
- **WHEN** the operation runs
- **THEN** it says which repositories changed and which did not
- **AND** every backup ref made is named, including for repositories left alone

### Requirement: A remembered choice never spans repositories

A choice remembered for one repository SHALL NOT be applied to another.

`Only the choice that loses nothing may be remembered` bounds what may be
remembered at all. This bounds where: an estate makes "do not ask again" into a
decision about two hundred repositories taken while looking at one, which is a
scope nobody consented to. The remembered answer stays with the repository it was
given for.

#### Scenario: a choice made in one submodule

- **GIVEN** a remembered choice recorded while acting on `svc-3`
- **WHEN** the same operation is asked for in `svc-47`
- **THEN** it is asked, because the choice was about `svc-3`

