# project-trust Specification

## ADDED Requirements

### Requirement: A remote git could not be asked about leaves the project undecided

A project SHALL be left undecided, not recorded as having no remote, when its
remote could not be asked because git cannot run on this machine: no trust
strip SHALL be shown for it, and its remote SHALL be asked again when git
runs. A project is only ever called untrusted on an answer git gave.

#### Scenario: trust by host while git cannot run

- **GIVEN** a project whose `origin` is on a trusted host, on a machine where
  the git shim refuses to run
- **WHEN** the project is opened
- **THEN** the git-availability strip is shown and the trust strip is not

#### Scenario: git runs again

- **GIVEN** that project, and git running once more
- **WHEN** the application becomes active
- **THEN** the remote is asked, the host matches, and the project is trusted
  without anybody trusting it again
