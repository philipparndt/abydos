## MODIFIED Requirements

### Requirement: A driven run opens what it was given, and types only into that

A driven run SHALL open what it was given, SHALL stay on it, and SHALL type only
into that.

A run with no project named opens no project. The app opening where somebody
left off is right for a launch from the Dock and wrong for every one of the
verbs, which are about a project somebody named — and it is how a typing verb
came to be pointed at a checkout nobody had mentioned. A run given files but no
project opens the project those files are in.

**And it stays there.** Opening the right project is not enough on its own: 0534
is a run that opened exactly what it was given and was moved off it seconds
later by a mechanism written for somebody working in a window. The project a
driven run shows is decided once, at launch, and nothing afterwards changes it —
not a terminal reporting where its shell has gone, not a restored session, not a
recent-projects entry. The rule is "opens what it was given **and stays there**".

**A driven run that cannot open the project it was named fails rather than
substituting.** If the named project does not exist, is not a directory, or
cannot be opened for any other reason, opening a different one is the worst
available answer: it is the answer that lets an agent type into somebody's real
files while believing it is driving a throwaway copy. The run writes the path it
could not open to standard error and exits non-zero, so a harness can act on it.

**A driven run says which project root it opened**, once, standardised. A scratch
copy is reached through macOS's symlinked `/tmp`, so the path a harness passed
and the path the app resolved are not the same string, and only the app can say
which one it settled on.

Every verb that changes text — the typing family, and `--emacs-nav`, whose ⌃O
opens a line and whose ⌃K takes one away — asks whether the file in front is one
this run named. A file it did not name is refused by name on standard error.
Being inside the project the run was given is not enough: the file has to be the
file that was asked for.

#### Scenario: a typing verb with no file named

- **Given** `--open <a project> --type "C"`, and a file in front from any other
  source
- **Then** nothing is typed, and the refusal names the file it declined

#### Scenario: a verb with no project named

- **Given** `--type "C"` and nothing else
- **Then** no project opens, rather than the one that was open last

#### Scenario: a file the run did name

- **Given** `--open <a project> --file main.swift --type "C"`
- **Then** the `C` arrives in `main.swift`

#### Scenario: the project cannot be opened

- **Given** `--open <a path that does not exist> --type "C"`
- **Then** no window opens, and no other project is opened in its place
- **And** standard error names the path
- **And** the process exits non-zero

#### Scenario: a scratch copy reached through a symlink

- **Given** `--open /tmp/<copy>` on macOS, where `/tmp` is a symlink to
  `/private/tmp`
- **Then** the window shows that copy
- **And** the root the run reports is the standardised path, not the path as typed

#### Scenario: the project cannot change afterwards

- **Given** a driven run showing the project it was given
- **When** anything asks the window to switch project — a pane reporting a
  directory, a restored session, a menu a verb clicked
- **Then** the window is still on the project the run was given

## ADDED Requirements

### Requirement: A flag that names its output produces that output alone

A driver flag taking a path to write SHALL, when passed on its own, either write the
content it names or fail visibly. It SHALL NOT write an empty or placeholder file and
exit zero, and it SHALL NOT require another flag to be passed beside it.

`--sidebar-shot <path>` names its own output file, so it plainly means "take this
picture". Needing `--screenshot` beside it to make it work is a coupling nobody can
guess and nothing states, and what came out instead was a blank pane, a written file
and a zero exit — which reads as "the sidebar had nothing in it". That is the
conclusion the agent capturing 0525's dependencies section would have written down.

A flag that silently produces a wrong answer is worse than one that refuses, because
the wrong answer is indistinguishable from evidence.

#### Scenario: a sidebar picture asked for by itself

- **Given** `--sidebar-shot <path>` and no `--screenshot`
- **Then** the file at `<path>` shows the sidebar as it is on screen
- **And** the process exits zero

#### Scenario: a capture that cannot be taken

- **Given** a flag naming an output that cannot be produced
- **Then** standard error says which flag and why
- **And** the process exits non-zero, and no file is written at the named path

### Requirement: Setting a run up for a capture asks whether it is driven, not which flag was passed

Behaviour existing so that a picture can be taken SHALL apply to every run that
produces one, and SHALL be gated on the run being driven rather than on
`screenshotPath` being set. Where a behaviour genuinely suits only a full screenshot,
the two questions SHALL be asked separately, each at the site that means it.

`isScreenshotRun` is `screenshotPath != nil`, and it is asked at some twenty sites
that mean two different things by it: "this run is going to write a picture, so set
the app up for it", and "`--screenshot` was passed". The two coincided while
`--screenshot` was the only capture flag, and the gap between them is the whole of
this change — 0535 is what it costs at a capture's setup, and 0534 is what it costs
at the terminal-follow guard, where the comment already argues for the broader rule
it does not test for.

#### Scenario: a sidebar-only run is set up like any capture

- **Given** a run passing only `--sidebar-shot`
- **Then** the project panel is skipped, as it is for `--screenshot`, so that nothing
  blocks on a modal
- **And** every other behaviour that exists so a picture can be taken applies

#### Scenario: a behaviour that suits only a full screenshot

- **Given** a site behind the gate that is right for `--screenshot` and wrong for a
  sidebar-only run
- **Then** it asks whether `--screenshot` was passed, and not whether the run is
  producing a picture
- **And** the two questions are separate properties, so neither site can drift into
  meaning the other

#### Scenario: a capture flag written tomorrow

- **Given** a flag added after this was written that names a picture to produce
- **Then** the capture setup applies to it without anybody having said so, the way
  "A run given a launch verb is a driven run" already works
