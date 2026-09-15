# Git availability

## ADDED Requirements

### Requirement: The window says when git cannot run, and how to fix it

The window SHALL show a strip across its top, in the place the trust strip
takes, whenever a git call was refused by the system's git shim — Xcode's
licence unaccepted, or no developer tools installed — saying that git cannot
run, why, and the one command that fixes it, with a button that copies the
command. The strip SHALL have no way to dismiss it and SHALL go away by itself
when a git call succeeds. Detection SHALL read what the shim says on stderr,
because the shim exits 0.

Reported 2026-09-15: after an Xcode update, every project asked to be trusted
again and the git pane was empty, and nothing in the window said that git had
not run once all morning.

#### Scenario: the licence is not accepted

- **GIVEN** a machine whose Xcode licence has not been accepted
- **WHEN** a project is opened
- **THEN** the strip reads that git cannot run because Xcode's licence has not
  been accepted, and offers `sudo xcodebuild -license accept`

#### Scenario: no developer tools

- **GIVEN** a machine with neither Xcode nor the Command Line Tools
- **WHEN** a project is opened
- **THEN** the strip says no developer tools are installed and offers
  `xcode-select --install`

#### Scenario: an ordinary git failure

- **GIVEN** git running, and a folder that is not a repository
- **WHEN** the folder is opened
- **THEN** no strip is shown

### Requirement: Git is asked again when the app comes back

While the strip is up, the application SHALL run one `git --version` when it
becomes active, and SHALL take the strip down and re-ask the current project's
remote when that call succeeds, so that accepting the licence in a terminal and
switching back is the whole of the fix.

#### Scenario: the licence is accepted in a terminal

- **GIVEN** the strip up over a project trusted by its remote
- **WHEN** the licence is accepted and the application is brought to the front
- **THEN** the strip is gone, the project is trusted, and no trust strip is
  shown
