## MODIFIED Requirements

### Requirement: A row's action can be reached from the keyboard

Every action a row offers SHALL be reachable without a mouse.

An action drawn on a row when the pointer is over it is a mouse-only feature,
and these panes have just been fixed not to be: the arrows walk them, `←` and
`→` open and shut them, and a verb that only a pointer can reach undoes that.

`⏎` is taken — on a branch it checks it out — so a row that has both a default
gesture and an action needs the two told apart rather than overloaded. What the
keyboard offers SHALL be the same set the pointer offers, and the context menu
remains the place where everything is named.

A tag row's delete SHALL be one of those actions: the tags section is not the
one place in this tree where a row's own verb is reachable by pointer only.

#### Scenario: the repository row from the keyboard

- **GIVEN** the repository row selected and a branch behind its upstream
- **WHEN** the key that fires a row's action is pressed
- **THEN** it pulls, as pressing the row does

#### Scenario: a branch row, which has both

- **GIVEN** a branch row selected
- **THEN** `⏎` checks it out, and the row's other verbs are reachable by their
  own gesture and from the context menu

#### Scenario: a tag row's delete

- **GIVEN** a tag row selected
- **THEN** its delete is reachable from the keyboard and named in the context menu
