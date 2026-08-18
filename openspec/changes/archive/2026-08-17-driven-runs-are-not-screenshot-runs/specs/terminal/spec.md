## MODIFIED Requirements

### Requirement: A window follows its terminal out of the project, and nowhere else

A window SHALL follow its terminal out of the project, and nowhere else.

A window can be asked to follow its terminal: when the shell in the pane in
front moves to another project, the window changes to that project, keeping
what each had open. What makes that bearable to leave switched on is that
moving *within* a project changes nothing — a `cd` into `Sources` is somebody
going about their work, not somebody leaving.

Within **the project**, which is not the same as within the repository around
it. A project opened at a subdirectory of a checkout — a package inside a
monorepo, one example inside a folder of them — has a repository above it that
answers for every directory in it, including its own. Reading "which repository
is this directory in" as "where has the shell gone" made every such project
throw itself away for the checkout about a second after it was opened, for a
shell that was sitting exactly where it had been put; the tabs somebody had
just opened were replaced by the checkout's own restored session, and nothing
said so.

So the question the window asks is about the project it is on: a directory
inside it is not a move, and only a directory outside it is. A shell that walks
out — `cd ..` into the checkout, or into any other repository — is followed as
it always was, because that is a person navigating rather than the app reading
its own restore back to itself. A directory belonging to no repository at all
leaves the window where it is.

**A driven run is the one exception and keeps its own rule: a run given any
launch verb never follows its terminal anywhere.** The window is showing a
project somebody named on the command line, and a pane whose shell sits in a
different checkout would swap it without complaint. Following a terminal is a
gesture, and a driven run has nobody making gestures.

The exception used to be written as "while a screenshot is being taken", and
guarded with `isScreenshotRun` — which is `screenshotPath != nil`. That is
narrower than the sentence it was standing for, and 0534 is what it cost: a run
given `--open`, `--file` and `--print-text` but no `--screenshot` was not a
capture by that test, so the guard let it through, and the window followed a
shell whose working directory had been deleted underneath it into
`~/.config/zshutil`, discarding the tab `--file` had opened. The rule is about a
project somebody named, and every driven run has one.

#### Scenario: a project opened at a subdirectory of a checkout

- **Given** a window following its terminal, opened on `checkout/models`
- **And** its terminal is in `checkout/models`, where the window put it
- **When** the terminal reports where it is
- **Then** the window is still on `checkout/models`, with the tabs it opened

#### Scenario: a shell moving deeper into the project

- **Given** that window, on `checkout/models`
- **When** the shell changes directory to `checkout/models/Sources`
- **Then** the window is still on `checkout/models`

#### Scenario: a shell that really leaves

- **Given** that window, on `checkout/models`
- **When** the shell changes directory to `checkout`
- **Then** the window changes to `checkout` and restores what it had open

#### Scenario: a shell in a directory that is in no repository

- **Given** that window, on `checkout/models`
- **When** the shell changes directory to a folder with no repository above it
- **Then** the window is still on `checkout/models`

#### Scenario: a driven run that takes no picture

- **Given** a run with `--open <a project> --file main.swift --print-text`, and
  no `--screenshot`
- **And** `followsTerminalProject` is true in the preferences the run copied
- **When** a pane reports a working directory outside the project — because its
  shell inherited a deleted directory and zsh fell back
- **Then** the window is still on the project it was given
- **And** the tab `--file` opened is still open

#### Scenario: a capture, as before

- **Given** a run with `--screenshot`
- **When** a pane reports a working directory in another checkout
- **Then** the window does not follow it
