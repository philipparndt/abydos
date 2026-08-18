# Screenshots

## Requirement: A capture is a picture of the app, not of the machine it was taken on

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

### Scenario: an agent finishes while the picture is being taken

- **Given** two runs of the same capture, on the same project
- **When** a Claude Code hook announces a finished session during the second of
  them, and nothing announces anything during the first
- **Then** the two pictures are identical, byte for byte

### Scenario: a picture of a toast

- **Given** a capture run that asks for a toast
- **Then** the toast is in the picture, in the corner, as it is on screen

### Scenario: the app somebody is working in

- **Given** a capture running while an ordinary window of the app is also open
- **When** a Claude Code hook announces a finished session
- **Then** the ordinary window still says so in its corner

## Requirement: A run given a launch verb is a driven run, and nothing has to remember to say so

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

### Scenario: a verb that takes no picture

- **Given** `--switch-appearance dracula`, which sets no screenshot path
- **Then** the run is a driven one, exactly as a run with `--screenshot` is

### Scenario: opening something is not driving it

- **Given** `--open ~/dev/thing --file main.swift`
- **Then** the run is not a driven one, and behaves as a launch from the Dock

### Scenario: a verb nobody has written yet

- **Given** a launch option added to the app after this was written
- **Then** a run using it is a driven one, without anybody having said so

## Requirement: A driven run changes nothing that belongs to whoever is at the keyboard

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

### Scenario: a preference changed during a capture

- **Given** a run with `--switch-appearance dracula`
- **When** it has finished
- **Then** the appearance in `de.rnd7.ideai` is what it was before the run

### Scenario: the window somebody left open

- **Given** a driven run against any project
- **When** it has finished
- **Then** the saved window frame and the saved split positions are unchanged

### Scenario: a project a capture was pointed at

- **Given** a driven run against a project with no `.abydos` folder
- **When** it has finished
- **Then** the project has no `.abydos` folder, and nothing new in `git status`

## Requirement: A driven run opens what it was given, and types only into that

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

### Scenario: a typing verb with no file named

- **Given** `--open <a project> --type "C"`, and a file in front from any other
  source
- **Then** nothing is typed, and the refusal names the file it declined

### Scenario: a verb with no project named

- **Given** `--type "C"` and nothing else
- **Then** no project opens, rather than the one that was open last

### Scenario: a file the run did name

- **Given** `--open <a project> --file main.swift --type "C"`
- **Then** the `C` arrives in `main.swift`

### Scenario: a project that is not there

- **Given** `--open /nowhere --sidebar-shot out.png`
- **Then** nothing opens, the path is named on standard error, and the run exits
  non-zero

### Scenario: which directory it actually opened

- **Given** any driven run that opens a project
- **Then** it says on standard error which root that resolved to, so that `/tmp`
  and `/private/tmp` — two names for one directory — cannot be confused for two

## Requirement: A driven run does not follow its terminal anywhere

**The window follows its terminal for somebody working in it, and never for a
run being driven.** A driven run is about a named project; a shell whose working
directory has been deleted underneath it reports somewhere else, and the window
went there — reproduced five times out of five. Everything the run then did, it
did to whatever that window had open.

The guard is on the driving and not on the picture. Asked as "was `--screenshot`
given", it did not cover a run with a verb and no capture at all, which is how
this arrived as two separate reports: a project switch nobody asked for, and a
sidebar capture that photographed a blank pane because the window had gone
somewhere with nothing loaded. **They are one fault** — established by reverting
the one line and watching the blank picture come back.

It is guarded at both places a pane's report can move the window, rather than by
filtering what a driven run is allowed to read.

### Scenario: a terminal whose directory has gone

- **Given** a driven run on a named project, and a shell reporting somewhere else
- **Then** the window stays on the project the run was given

### Scenario: somebody working in a window

- **Given** no driven verb, and the follow setting on
- **Then** the window follows the terminal, exactly as before

## Requirement: Every capture flag is a capture

The question "is this run going to write a picture" SHALL be asked of every flag
that writes one, not of `--screenshot` alone. While that was the only capture
flag the two were the same sentence; they stopped being so and nothing noticed,
and a run given only `--sidebar-shot` reached an `exit(0)` written for "no
picture is coming" — ending the process before the capture, and reporting
success.

A capture that cannot be produced says so on standard error and exits non-zero.
A capture that can be produced ends the run: `--sidebar-shot` used to write its
file and then sit there, so every use of it needed a `timeout`, and a run killed
by one reports 124 whether or not the picture was written.

### Scenario: a capture flag on its own

- **Given** `--open <project> --sidebar-shot out.png`, with no `--screenshot`
- **Then** the picture is of the sidebar as it is on screen
- **And** the run exits zero when it wrote one

### Scenario: a capture that cannot be produced

- **Given** a capture flag and nothing to capture
- **Then** nothing is written, the failure is named, and the status is non-zero
