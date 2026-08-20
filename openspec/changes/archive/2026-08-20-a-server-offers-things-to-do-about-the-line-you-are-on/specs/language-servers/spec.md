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
There SHALL be a keystroke that asks, whatever else is shown: ⌥⏎.

**And it SHALL be a keystroke rather than a mark, which was measured rather than
preferred.** Asked at the first non-space character of every line of a real file,
gopls answered something about 16 lines of 16 and jdtls about 10 of 10 — organise
imports, generate accessors, and in gopls's case `gopls.doc.features`, a kind of
its own invention outside the protocol's hierarchy. **Filtering the file-wide
kinds does not save it**: gopls is still at 16 of 16 with `source.*` removed. So
nothing that means "there is something here" may be driven by whether the list is
empty; the only always-on affordance left standing is the diagnostic, which is
drawn where something is wrong and nowhere else.

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

## MODIFIED Requirements

### Requirement: A server can change the code, and rename is what it is asked for

A server SHALL be able to change the code. **Rename was the first thing asked of
it and is no longer the only one**: what a server *offers* about a place in a
file is asked for too, and taken the same way — see *A server's offers about the
line you are on can be seen and taken*. Both end in one workspace edit, applied
by one machinery.

Everything else this program asks a language server is a question. Renaming a
symbol was the first thing it asked that changes files, and it changes many of
them at once: the answer is a *workspace edit*, and one of those from a real
project arrives about a hundred files in six directories, none of which anybody
had open.

Rename ▸ from the code's context menu, or ⇧F6, which is IDEA's. **The new name
is typed where the old one is** — a field laid over the symbol, in the text,
scrolling with it — rather than in a dialog. It is the navigator's in-place
rename on a row, one layer in: the thing being renamed is on screen, the new
name goes where the old one is, and the rest of the window carries on. Return
takes it, Escape drops it, clicking away takes it, and a name that is refused
leaves the field standing with the text still in it, because a name that is not
allowed is a typo far more often than it is a change of mind.

#### Scenario: renaming a symbol used in several files

- **Given** a project with a server running, and a symbol used in three files of
  which one is open
- **When** it is renamed from the editor
- **Then** all three files say the new name
- **And** the open one says it in its editor as well as on disk

#### Scenario: the caret is not on anything renameable

- **Given** the caret on a bracket
- **When** a rename is asked for
- **Then** nothing is said and no field appears
