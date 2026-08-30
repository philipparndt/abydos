# git-safety

## ADDED Requirements

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
