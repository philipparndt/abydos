## ADDED Requirements

### Requirement: A preview run is told not to reveal what it writes

The run that builds a Cadova model SHALL tell Cadova not to reveal the file it
writes.

Cadova reveals its output in the Finder when a build finishes, which is right
for somebody who ran `swift run` themselves and wrong for a pane that runs it
again on every save of any of the target's sources. The setting SHALL be made
in the environment of that run — the process this app starts — and SHALL NOT be
required of the model's own code: a model from anybody's repository has no
reason to know this app exists.

The run's environment SHALL be this process's own with that one variable added.
Replacing it would leave the run without a `PATH`, a `HOME` or anything else the
toolchain it starts needs.

The name of the variable SHALL be spelled in one place beside the command the
run is, so that a rename upstream is one line rather than a search.

#### Scenario: a model rebuilt on save

- **GIVEN** a Cadova model open in the preview
- **WHEN** one of its target's sources is saved and the pane rebuilds
- **THEN** the model is redrawn and no Finder window is opened

#### Scenario: a model that never heard of this app

- **GIVEN** a Cadova model whose code does not set `isFileRevealingEnabled`
- **WHEN** it is previewed
- **THEN** it behaves the same as one that does

#### Scenario: the run still finds its toolchain

- **GIVEN** a `swift` that a version manager owns rather than the system
- **WHEN** the preview builds
- **THEN** the run has the environment it had before, with only that variable
  added
