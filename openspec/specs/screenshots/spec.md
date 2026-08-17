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

A driven run SHALL open what it was given, and SHALL type only into that.

A run with no project named opens no project. The app opening where somebody
left off is right for a launch from the Dock and wrong for every one of the
verbs, which are about a project somebody named — and it is how a typing verb
came to be pointed at a checkout nobody had mentioned. A run given files but no
project opens the project those files are in.

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
