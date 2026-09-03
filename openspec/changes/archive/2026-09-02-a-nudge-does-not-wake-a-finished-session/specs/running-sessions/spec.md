## ADDED Requirements

### Requirement: A nudge does not wake a finished session

The register SHALL leave a `done` record as it is when a `Notification` that is
only Claude's idle nudge, or a `SubagentStop`, arrives for that session, SHALL
report the event as no move, and SHALL NOT let it be announced in the corner. The
register SHALL be able to say so before the event is recorded, so the corner can
ask.

This is the rule the hook already keeps for a session in tmux, where the window's
own badge says `done`; outside tmux the hook has no memory, and the register is
it. A nudge for a session that was working, or a notification that is a real
question — a permission prompt, `agent_needs_input` — is unaffected.

#### Scenario: the idle nudge a minute after an answer

- **GIVEN** a session outside tmux whose record says `done`
- **WHEN** a `Notification` of type `idle_prompt` arrives for it, with status `needs`
- **THEN** the record still says `done`, the pill's counts do not move, and no toast is raised

#### Scenario: a subagent finishing after the turn ended

- **GIVEN** a session whose record says `done`
- **WHEN** a `SubagentStop` arrives for it
- **THEN** the record still says `done` and nothing is announced

#### Scenario: a nudge for a session that was working

- **GIVEN** a session whose record says `working`
- **WHEN** a `Notification` of type `idle_prompt` arrives for it, with status `needs`
- **THEN** the record says `needs`, and the row turns amber

#### Scenario: a real question after a finished turn

- **GIVEN** a session whose record says `done`
- **WHEN** a `Notification` of type `permission_prompt` arrives for it, with status `needs`
- **THEN** the record says `needs`
