## ADDED Requirements

### Requirement: A server's offers about the line you are on can be seen and taken

The editor SHALL ask a server what it offers about the current selection —
`textDocument/codeAction` — and SHALL carry the diagnostics under that selection
in the request, because what a server offers depends on what it last published
and not only on where the caret is.

**An action that arrives without an edit SHALL be resolved before it is
applied.** A server may answer cheaply and fill in the work on
`codeAction/resolve` for the one that was chosen; treating an unresolved action
as an empty edit is a menu that works and does nothing.

**An action that carries a command rather than an edit SHALL be executed as
one**, through `workspace/executeCommand`. The server may then ask the client to
apply an edit through `workspace/applyEdit` — an inbound request that changes
files — and that request SHALL be answered with whether the edit was applied,
including `false` when it was not.

Every edit SHALL be applied through the machinery that already applies a
`WorkspaceEdit`: open documents through the rope, closed ones on disk, as one
undo, with file moves, and an honest refusal when part of it cannot be done.

**There SHALL be a way to see that actions exist without it becoming noise.**
An action is offered rather than asked for, so something has to say that there is
something on offer — and a mark present on every line is a mark nobody reads.
There SHALL be a keystroke that asks, whatever else is shown.

`source.*` actions are about the file rather than a position, and SHALL be
reachable somewhere other than a menu that appears at the caret.

#### Scenario: a quick fix for a diagnostic

- **GIVEN** a file with a diagnostic the server can fix
- **WHEN** the actions for that line are asked for
- **THEN** the fix is offered, and taking it applies the server's own edit

#### Scenario: an action that arrives empty

- **GIVEN** a server that answers with actions carrying no edit
- **WHEN** one is taken
- **THEN** it is resolved first, and the resolved edit is what is applied

#### Scenario: an action that is a command

- **GIVEN** an action carrying a command
- **WHEN** it is taken
- **THEN** the command is executed
- **AND** an edit the server sends back is applied and answered for

#### Scenario: an edit that cannot be applied

- **GIVEN** a server asking to edit a file this app cannot write
- **THEN** the request is answered saying it was not applied, rather than
  optimistically

#### Scenario: nothing on offer

- **GIVEN** a line the server offers nothing about
- **THEN** nothing is shown, and asking says so plainly
