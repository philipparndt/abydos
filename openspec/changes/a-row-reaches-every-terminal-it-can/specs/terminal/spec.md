## ADDED Requirements

### Requirement: A pane names itself to what runs in it

Every shell the panel starts SHALL find `ABYDOS_TERMINAL` in its environment,
set to the identity of the tab it runs in — set, as `TERM_PROGRAM` is, rather
than inherited, since an inherited value would name the tab the app itself was
launched from.

A program in that pane can then say which tab it is in: the Claude hook sends
the value with its events when it is not inside tmux, and the running-sessions
list uses it to bring the tab forward. Inside tmux the variable is the tmux
server's inheritance and is not sent; the tmux place is.

#### Scenario: a shell in the second tab

- **GIVEN** two `Local` tabs
- **WHEN** `echo $ABYDOS_TERMINAL` is run in the second
- **THEN** it prints the second tab's identity, and the first tab's shell prints a different one

#### Scenario: a hook outside tmux

- **GIVEN** a Claude session started in a `Local` tab
- **WHEN** it sends an event
- **THEN** the event carries the tab's identity and no tmux place
