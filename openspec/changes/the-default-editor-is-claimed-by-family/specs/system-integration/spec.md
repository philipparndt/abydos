## MODIFIED Requirements

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
words. The system's own confirmations SHALL be kept few: the bundle SHALL
declare the parent kind of the text kinds it edits, the call SHALL be made
for the kinds that conform to no other declared kind first, and then only for
the kinds Launch Services still does not resolve to this application.

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

#### Scenario: the system's dialogs

- **GIVEN** *Use Abydos* chosen and no other application binding a text kind by name
- **THEN** the system confirms once, for text, and every declared kind then opens here

#### Scenario: a kind another application holds

- **GIVEN** Xcode bound to `public.source-code` by name
- **WHEN** *Use Abydos* is chosen
- **THEN** the system confirms for text and then once more for source code, and nothing else
