# Commit message drafts — delta

## MODIFIED Requirements

### Requirement: The draft is offered only when it can be made, and its cost is said

Drafting SHALL be visible and disabled when the `claude` command is not on the
`PATH`, with the reason on the control; it SHALL be absent only when there is
nothing it could ever describe. The first use in a project SHALL say that the
staged diff is sent to Anthropic.

The old rule made the control *absent* when the command was missing, on the
argument that a control that fails when pressed is worse than one that is not
there. That argument stands and is not what absence bought: a disabled control
cannot be pressed and so fails nothing, while an absent one cannot be
discovered — the feature was requested, on 2026-08-31, by somebody on whose
machine it already existed and was hidden. The push button is the pane's own
precedent: disabled, it says why. Sending somebody's diff off the machine is
still said plainly, once, before it happens rather than after.

#### Scenario: the command is not installed

- **GIVEN** a machine with no `claude` on the `PATH`
- **THEN** the commit page shows the drafting control disabled, and its
  tooltip says the `claude` command was not found

#### Scenario: installing the command enables it

- **GIVEN** the disabled control
- **WHEN** `claude` becomes findable and the pane refreshes
- **THEN** the control is enabled, without a restart

#### Scenario: the first draft in a project

- **GIVEN** a project in which drafting has not been used
- **WHEN** a draft is asked for
- **THEN** it is said that the staged diff will be sent, and it is asked for once
