## ADDED Requirements

### Requirement: Next Tab and Previous Tab follow the keyboard

*Next Tab* (⌘⇧]) and *Previous Tab* (⌘⇧[) SHALL, while the keyboard is in the
panel, select the neighbouring tab on the strip of the column being typed in,
wrapping at either end, and SHALL give that tab the keyboard as a click on it
does. While the keyboard is in the editor they SHALL act on the editor's tabs, as
they always have.

Where tmux's windows have a strip of their own along the bottom, the top strip's
tabs — the `tmux` tab and the panel's own terminals and panes — are what the keys
move between, and tmux's windows keep tmux's own keys; a top strip holding a
single tab over such a strip SHALL cycle the windows instead, since those are
the tabs on show. Where tmux's windows share the one strip, they are among the
tabs the keys move between.

#### Scenario: from a terminal to the tmux tab and back

- **GIVEN** a panel strip holding `tmux`, `Local`, `Local`, with the keyboard in the second `Local`
- **WHEN** ⌘⇧] is pressed
- **THEN** the `tmux` tab is in front and has the keyboard
- **WHEN** ⌘⇧[ is pressed
- **THEN** the second `Local` is in front again

#### Scenario: the editor keeps its keys

- **GIVEN** the same panel, with the keyboard in the editor
- **WHEN** ⌘⇧] is pressed
- **THEN** the editor's next tab is in front and the panel's strip is unchanged

#### Scenario: only the tmux tab over its own strip

- **GIVEN** a top strip holding only `tmux`, with tmux's windows on a strip below it
- **WHEN** ⌘⇧] is pressed with the keyboard in the terminal
- **THEN** the next tmux window is selected
