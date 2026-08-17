<!-- What this item changes about `sessions`. Folded into
     .abydos/backlog/spec/sessions.md by `abydos-backlog done`.
-->

## ADDED Requirement: A driven run neither restores a session nor writes one

A session is what a person left behind, and a run being driven from the command
line is not that person. So a run given a launch verb opens the files it was
given and no others, starts no terminal the session had, attaches to no tmux
session the project remembers, and writes nothing back when it ends.

This is the half of it that matters most, because what is on screen is what a
driven verb types into. A window that had restored somebody's tabs and somebody's
shell is a window where `--type` reaches a source file nobody was editing and a
keystroke reaches a shell somebody is standing in — which is what happened, and
what three separate items were filed about before the cause was found.

Nothing about how a session is written or read otherwise changes: the same file,
beside the same project, restored the same way for anybody opening it themselves.

### Scenario: a typing verb against a project with tabs to restore

- **Given** a project whose session names an open file
- **When** a run with a launch verb opens that project
- **Then** the file is not opened, and the session file on disk is unchanged

### Scenario: what a driven run leaves in the project

- **Given** a driven run that opens a project, opens files in it, and ends
- **Then** the project's session file says what it said before the run

### Scenario: somebody opening the project themselves

- **Given** the same project opened with no launch verb
- **Then** the session is restored and written exactly as it always was
