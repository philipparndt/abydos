## ADDED Requirements

### Requirement: The register counts a session's subagents

The register SHALL keep, per running session, how many subagents it has out:
raised by a `PreToolUse` whose tool is the one that spawns a subagent, lowered
by a `SubagentStop`, never below nought, and set to nought when a turn ends.

The reset is what keeps it honest. A `SubagentStop` can go missing — the app was
not running, the subagent was killed — and a count that only rose would be
wrong for the life of the session. A finished turn has no subagents running,
whatever was missed in it.

The tool's name SHALL be read from the event the hook was given rather than
assumed. Where the name does not match, the count SHALL stay at nought, so a
guess that is wrong reads as a session with no subagents rather than as a wrong
number.

#### Scenario: two sent off and one back

- **GIVEN** a working session
- **WHEN** it sends two `PreToolUse` events for the spawning tool and then one `SubagentStop`
- **THEN** the register says it has one subagent out

#### Scenario: a turn that ends

- **GIVEN** a session with two subagents out
- **WHEN** its turn ends
- **THEN** the register says it has none

#### Scenario: more back than went out

- **GIVEN** a session with no subagents out
- **WHEN** a `SubagentStop` arrives
- **THEN** the count is nought and not below it

#### Scenario: an ordinary tool use

- **GIVEN** a working session
- **WHEN** it sends a `PreToolUse` for reading a file
- **THEN** the count is nought

### Requirement: A row says how many subagents are out

A row in the popover SHALL say how many subagents its session has out when it
has any — beside what the session last said, in the same dimmed trailing text —
and SHALL say nothing about them when it has none, because a count of nought is
not news.

#### Scenario: a session with subagents

- **GIVEN** a session with two subagents out
- **THEN** its row reads `2 subagents` after its last line

#### Scenario: a session working alone

- **GIVEN** a working session with no subagents
- **THEN** its row says nothing about subagents
