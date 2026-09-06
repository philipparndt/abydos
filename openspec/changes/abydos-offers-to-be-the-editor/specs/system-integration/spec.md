## ADDED Requirements

### Requirement: The bundle declares the files this editor can open

The application SHALL declare, as document types, the kinds of file its editor
reads — the extensions `LanguageRegistry` knows and the formats its previews
handle — so that the Finder lists it under *Open With* for a source file and a
file dropped on its icon is opened. Each SHALL be declared with the role of an
editor and the rank of an alternate, never an owner: appearing in the menu is
an offer, and claiming a type is somebody's decision rather than an
installation's. A kind of file the editor cannot read SHALL NOT be declared,
whatever it would cost to add.

#### Scenario: a source file in the Finder

- **GIVEN** a `.swift` file and this application installed
- **WHEN** its *Open With* menu is read
- **THEN** Abydos is in it

#### Scenario: a file the editor cannot read

- **GIVEN** a `.psd` file
- **WHEN** its *Open With* menu is read
- **THEN** Abydos is not in it

#### Scenario: nothing is claimed by installing

- **GIVEN** a fresh installation and a `.json` file whose default is another editor
- **WHEN** the file is double-clicked
- **THEN** the other editor opens it, as it did before

### Requirement: Being made the default is asked for once, and can be refused for good

The application SHALL ask whether it should become the default for the kinds of
file it declares the first time a source file is opened in a window — not at
first launch, which is a question about nothing that has happened yet. The ask
SHALL offer three answers: making it the default, not now, and never asking
again; and SHALL remember which was given, so that it is asked once whatever
the answer.

Making it the default SHALL go through the system's own call, and what the
settings page then shows SHALL be read back from Launch Services rather than
from what was asked for, since the system may refuse or ask again in its own
words.

#### Scenario: the first source file

- **GIVEN** a fresh installation
- **WHEN** a `.swift` file is opened in a window
- **THEN** the app asks once whether it should be the default for source files

#### Scenario: not now

- **GIVEN** that ask answered with *Not Now*
- **WHEN** another source file is opened
- **THEN** nothing is asked again, and no default was changed

#### Scenario: never ask

- **GIVEN** that ask answered with *Never Ask*
- **THEN** nothing asks again, and the settings page still offers the choice

#### Scenario: the page says what the system believes

- **GIVEN** the default for `.swift` taken by another application after Abydos was made the default
- **WHEN** the settings page is read
- **THEN** it shows the other application, because it asks Launch Services rather than remembering its own answer

### Requirement: The choice can be made and undone in the settings

The settings SHALL carry the same choice the ask carries: which kinds of file
Abydos is the default for, made or handed back without waiting to be asked.
Handing them back SHALL say what will happen before it is pressed, since the
system decides what takes them next.

#### Scenario: making it the default later

- **GIVEN** the ask answered with *Never Ask*
- **WHEN** the settings row is switched on
- **THEN** Abydos becomes the default for the declared kinds

#### Scenario: handing them back

- **GIVEN** Abydos as the default for source files
- **WHEN** the row is switched off
- **THEN** the types are no longer this application's, and what said so was said before the press

### Requirement: A terminal can be opened at a folder from the Finder

The application SHALL offer a service — *New Terminal Here* — on a folder and
on a file, so that the Finder can put a terminal where somebody is standing: a
folder SHALL open the project it belongs to with the terminal at that folder,
and a file SHALL open at the folder holding it.

Where a window is already open on that project it SHALL be used, as every other
way of opening a project into this app does.

The settings SHALL say plainly that the Finder's own *Open in Terminal* belongs
to Terminal.app and cannot be pointed at another application, and SHALL say
where this service appears and where a keyboard shortcut is given to it —
because a page that offered neither would leave somebody hunting for a switch
macOS does not have.

#### Scenario: a folder in the Finder

- **GIVEN** a project folder selected in the Finder
- **WHEN** *New Terminal Here* is chosen from the Services menu
- **THEN** the project opens with its terminal at that folder

#### Scenario: a file rather than a folder

- **GIVEN** a source file selected
- **WHEN** the service is chosen
- **THEN** the terminal opens at the folder holding it

#### Scenario: a project already open

- **GIVEN** a window already showing that project
- **WHEN** the service is chosen on its folder
- **THEN** that window is used rather than a second one appearing

#### Scenario: what cannot be done is said

- **WHEN** the settings page is read
- **THEN** it says the Finder's own *Open in Terminal* cannot be redirected, and names where the service and its shortcut live
