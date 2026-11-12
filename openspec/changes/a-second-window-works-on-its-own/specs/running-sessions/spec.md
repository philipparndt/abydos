# Running sessions

## ADDED Requirements

### Requirement: A tmux window is counted once, however many sessions show it

A seeded record SHALL be keyed by the tmux window's own identity, `window_id`,
which the server gives each window once, and not by a session's name and the
window's index in it. Two sessions in one group list the same windows under two
names; keyed by name, one agent was two records and the pill counted it twice.

Forgetting what was seeded from a session a panel has stopped mirroring SHALL
NOT forget a record another panel's session still shows.

#### Scenario: two windows on one group

- **GIVEN** `AbydosDev` and its grouped session, mirrored by two windows, and the
  tmux window `Claude` badged `working`
- **WHEN** both mirrors read their sessions' windows
- **THEN** the pill's working count is one

#### Scenario: one window leaves the group

- **GIVEN** the same, and window 2 switched to another session
- **WHEN** window 2's mirror forgets what it seeded
- **THEN** `Claude` is still counted, from window 1's mirror
