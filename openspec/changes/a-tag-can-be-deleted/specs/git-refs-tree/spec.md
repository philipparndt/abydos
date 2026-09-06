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

A tag row's delete SHALL be one of those actions, on ⌘⌫ — the delete gesture
this app already has in the project tree — so the tags section is not the one
place in this tree where a row's own verb needs a pointer. The key SHALL act on
the selection or on nothing: where the selection is not all tags there is a
different question to ask, and no key answers two.

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
- **WHEN** ⌘⌫ is pressed
- **THEN** the tag's delete sheet opens, as choosing it from the context menu does

#### Scenario: the key on a selection that is not all tags

- **GIVEN** a branch row and a tag row selected together
- **WHEN** ⌘⌫ is pressed
- **THEN** nothing is asked and nothing is deleted
