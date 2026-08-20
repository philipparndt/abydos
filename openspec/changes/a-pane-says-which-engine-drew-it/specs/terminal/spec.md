## ADDED Requirements

### Requirement: A pane says which engine drew it

A pane SHALL be able to say which engine drew it, read from the engine it holds
rather than from the setting that asked for one.

Three facts are true separately and were indistinguishable: the setting is on;
*this pane* uses that engine; and that engine started. A pane picks its engine
when it is built, so a pane older than a setting change keeps what it was made
with — deliberately, because a running shell would lose its scrollback
otherwise — and a libghostty-vt that will not initialise falls back to our own
emulator, which is right and silent. So "I turned it on and I cannot tell" has
three possible true answers, and the app offered no way to choose between them.

**The non-default engine SHALL be what is shown.** A mark present in the
ordinary case is a mark nobody reads.

**A fallback SHALL be audible once.** Somebody who asked for libghostty-vt and
got our emulator because the library would not start SHALL hear it, rather than
discovering it in a launch flag.

#### Scenario: a pane drawn by the non-default engine

- **GIVEN** the setting on, and a pane opened after it was changed
- **THEN** the pane says libghostty-vt drew it

#### Scenario: a pane older than the setting

- **GIVEN** a pane opened before the setting was changed
- **THEN** it says our own emulator drew it, which is what it has

#### Scenario: the ordinary case

- **GIVEN** the setting off
- **THEN** nothing is marked

#### Scenario: the library will not start

- **GIVEN** the setting on and a libghostty-vt that fails to initialise
- **WHEN** a pane is opened
- **THEN** the fallback is said once
- **AND** the pane says our own emulator drew it
