## ADDED Requirements

### Requirement: A goal offered in many modules is named once

The run list SHALL show a goal that exists once per module as a single row that
says how many places it has, and SHALL list those places when the row is opened.

Measured on a reactor of 184 modules, discovery finds 683 runnable things and
nine distinct choices. A flat list of the 683 runs off the screen, and two
hundred and ninety-seven of its rows say the same three words.

#### Scenario: a goal in many modules

- **GIVEN** a reactor offering `mvn package` in 184 modules
- **WHEN** the run list is opened
- **THEN** it shows one row for `mvn package`, saying how many places it has

#### Scenario: opening one

- **WHEN** that row is opened
- **THEN** the places are listed, the reactor root first, each named by its
  module

#### Scenario: few enough places to show

- **GIVEN** a main class found in two modules
- **THEN** both are shown as rows, each with its module beside it, rather than
  folded behind one

### Requirement: A goal row does the same thing however it is activated

Activating a goal row SHALL open its places, whether by click, by Return or by
the right arrow.

A row that ran something on Return and opened on → was one row doing two
different things depending on how it was touched — and a mouse has no →, so
clicking a goal ran a build and shut the popover. Running at the reactor root is
the first row inside instead.

#### Scenario: clicking a goal

- **WHEN** a goal row is clicked
- **THEN** its places are listed, and nothing is started

#### Scenario: leaving one

- **WHEN** the row at the top of the places is clicked, or ← or Escape pressed
- **THEN** the list goes back, with the goal that was left still selected

### Requirement: The run list can be filtered by typing

The run list SHALL match what is typed against both the goal name and the module,
and SHALL rank a match in the name above a match in the module.

#### Scenario: typing a module

- **WHEN** a module name is typed
- **THEN** every goal available in that module is listed directly, without any
  of them having to be opened first

#### Scenario: what outranks what

- **GIVEN** a goal called `mvn clean` and a goal available in a module called
  `cleanup-tools`
- **WHEN** `clean` is typed
- **THEN** `mvn clean` is listed first
