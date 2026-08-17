<!-- What this item changes about `screenshots`. Folded into
     .abydos/backlog/spec/screenshots.md by `abydos-backlog done`.

     ADDED, MODIFIED and REMOVED. A rename is a REMOVED and an ADDED.
     Write each requirement as it will read in the spec, in the present
     tense — not as a description of the edit.
     The requirements already there, to name exactly:
       A capture is a picture of the app, not of the machine it was taken on
-->

## ADDED Requirement: A run given a launch verb is a driven run, and nothing has to remember to say so

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

## ADDED Requirement: A driven run changes nothing that belongs to whoever is at the keyboard

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

## ADDED Requirement: A driven run opens what it was given, and types only into that

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
