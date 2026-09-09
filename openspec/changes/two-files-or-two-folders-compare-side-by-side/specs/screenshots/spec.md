## ADDED Requirements

### Requirement: A driven run can open a compare page and walk it

A driven run SHALL open a compare page over two paths with `--compare <a>
<b>`, and SHALL walk it with `--compare-steps`, whose steps are the gestures
the page has — next and previous change, open row n, mark row n to copy or
delete, show equal rows, and filter text — in the shape `--changes-steps` and
`--hex` already take. `--screenshot` photographs the result as it does any
other page.

A driven compare page never applies its marks: what a driven run is forbidden
to touch on the machine it runs on includes the folders it was pointed at.

#### Scenario: a folder diff photographed

- **WHEN** the app is started with `--open <scratch> --compare <scratch>/a
  <scratch>/b --screenshot out.png`
- **THEN** `out.png` shows the folder diff of the two

#### Scenario: a walk that would apply

- **WHEN** `--compare-steps` marks a row and asks to apply
- **THEN** the mark is shown and nothing is copied or trashed
