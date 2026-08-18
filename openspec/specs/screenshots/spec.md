# Screenshots

## Purpose

Driving the app from the command line: taking pictures of it, typing into it, and asking it what it is showing. Covers what makes a run a driven one and what a driven run is forbidden to touch on the machine it runs on.
## Requirements
### Requirement: A capture is a picture of the app, not of the machine it was taken on

A capture SHALL be a picture of the app, not of the machine it was taken on.

The app photographs itself: `--screenshot <path>` renders the window into a PNG
from its own view tree, in process, which needs no Screen Recording permission
and draws through exactly the code the display uses. It is how the pictures in
`docs/` are made — `Scripts/screenshots.sh` takes every one of them — and how a
change to the interface is looked at without a person at the keyboard.

Everything about a capture that is otherwise remembered per machine is said
outright, because a picture that depends on the machine is a picture nobody else
can take again: the window is given a size, the panel a height, the palette is
named, and each project is copied to a temporary directory first.

What the machine happens to be *doing* is ruled out the same way. A Claude Code
session anywhere on the machine announces itself, through the hook, to every
running copy of the app, and each says so in the corner of its window; a copy
that is taking a picture does not, because whether somebody's agent finished in
the eight seconds before the shutter is not a fact about the program being
photographed.

It is news from outside the run that is declined, not toasts. Everything the run
itself causes still reaches the corner and is still photographed — a shot that
asks for a toast gets one, and a shot that provokes a real failure shows what
the app really says about it — because a capture that quietly left toasts out
could not be told from a capture of an app with nothing to say.

#### Scenario: an agent finishes while the picture is being taken

- **Given** two runs of the same capture, on the same project
- **When** a Claude Code hook announces a finished session during the second of
  them, and nothing announces anything during the first
- **Then** the two pictures are identical, byte for byte

#### Scenario: a picture of a toast

- **Given** a capture run that asks for a toast
- **Then** the toast is in the picture, in the corner, as it is on screen

#### Scenario: the app somebody is working in

- **Given** a capture running while an ordinary window of the app is also open
- **When** a Claude Code hook announces a finished session
- **Then** the ordinary window still says so in its corner

### Requirement: A run given a launch verb is a driven run, and nothing has to remember to say so

A run given a launch verb SHALL be a driven run, and nothing SHALL have to remember to say so.

The app has 191 launch-option verbs, and they are the only way anything in the
window layer is proved at all — there is no test target for it. They are run
dozens of times a day, on the machine somebody is working on.

A run is *driven* when it was given any `--verb` beyond the two that only say
what to open, `--open` and `--file`. Nothing is asked and no flag is passed: the
question is answered from the arguments, so a verb written tomorrow is isolated
on the day it is written and a driver that forgets is not a thing that can
happen. The rule is stated as "everything except those two" rather than as a
list of verbs, because a list is a thing that goes out of date silently.

It is safe in the direction it can be wrong. Being too eager costs a driven run
the ability to change somebody's machine, which is the whole point; and nothing
a person types can trip it, because the command line people use sends paths and
never a flag, a launch from the Dock sends none, and the single-dash arguments
the system adds are not counted.

#### Scenario: a verb that takes no picture

- **Given** `--switch-appearance dracula`, which sets no screenshot path
- **Then** the run is a driven one, exactly as a run with `--screenshot` is

#### Scenario: opening something is not driving it

- **Given** `--open ~/dev/thing --file main.swift`
- **Then** the run is not a driven one, and behaves as a launch from the Dock

#### Scenario: a verb nobody has written yet

- **Given** a launch option added to the app after this was written
- **Then** a run using it is a driven one, without anybody having said so

### Requirement: A driven run changes nothing that belongs to whoever is at the keyboard

A driven run SHALL change nothing that belongs to whoever is at the keyboard.

A driven run reads the machine and writes none of it. The preferences it starts
from are the ones the user has chosen — a capture of the app as somebody
actually has it is the point — but every write goes to a store that lives in
memory for the length of the run and is gone with the process. It does not
restore a session, does not write one, does not put a project into the list of
recent projects, does not record which scratches were open, and does not autosave
the window frame or the split positions.

The last of those is not this program's own writing: AppKit saves a window frame
and a split position through `UserDefaults` from inside the framework, under a
name the window is given. So a driven run is not given one. It reads the
remembered frame once, and a capture that wants a particular sidebar or panel
says so outright, which is what a picture that has to look the same on two
machines has always had to do.

#### Scenario: a preference changed during a capture

- **Given** a run with `--switch-appearance dracula`
- **When** it has finished
- **Then** the appearance in `de.rnd7.ideai` is what it was before the run

#### Scenario: the window somebody left open

- **Given** a driven run against any project
- **When** it has finished
- **Then** the saved window frame and the saved split positions are unchanged

#### Scenario: a project a capture was pointed at

- **Given** a driven run against a project with no `.abydos` folder
- **When** it has finished
- **Then** the project has no `.abydos` folder, and nothing new in `git status`

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

