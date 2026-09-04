## ADDED Requirements

### Requirement: Hiding tmux's status bar says whose bar it takes

Where the app offers to hide tmux's own status bar, it MUST say what that
reaches: it sets the option on the tmux *session* the panel is attached to, so
every terminal attached to that session draws no status bar either — inside this
app or not, then and afterwards — and the session keeps that setting when the
app quits, until the switch is turned off again.

It MUST also say what is left alone: no other session on the server, and nothing
written to the user's tmux configuration.

Turning the switch off SHALL restore whatever that session's own configuration
says, rather than a bar this app chooses, and SHALL say so in those terms.

#### Scenario: reading the switch

- **WHEN** the setting is read in the settings window
- **THEN** it names the session it acts on, says that every terminal attached to
  that session loses the bar, and says the setting outlives the app

#### Scenario: turning it on

- **WHEN** the bar is hidden
- **THEN** what is said names the session and the terminals it reaches

#### Scenario: turning it off

- **WHEN** the bar is restored
- **THEN** what is said is that the session's own configuration decides again,
  rather than repeating what was not written
