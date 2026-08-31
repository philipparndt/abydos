# Sessions

## Purpose

What a project remembers between one sitting and the next: which files were
open, how each was being shown, where the terminals were, what the play button
was pointing at. It is kept beside the project, so it belongs to the project
rather than to the application — switching to another project and coming back,
and closing the window and opening it again, are the same thing to it.

Only the tabs are described here so far. The terminals, the breakpoints, the
chosen configuration and the subproject are remembered too and none of them has
been written down yet; whoever touches one of them has a file to add to.

## Requirements

### Requirement: A tab comes back in the mode it was being shown in

A tab SHALL come back in the mode it was being shown in.

A file with both a source and a rendered form is shown in one of four modes —
the source, the rendered form, or one of the two splits — and which one is a
property of the tab. It is written into the session beside the path and the
line, so a tab put in Split Right is still in Split Right when the project it
belongs to is opened again. Switching project rebuilds the whole tab set, and a
relaunch builds it from the file on disk; both put back what was there.

#### Scenario: a model beside its source, across a project switch

- **Given** a `.scad` open in Split Right, with the model beside the source
- **When** another project is opened in the window and then that one again
- **Then** the tab is in Split Right, with the model still beside the source

#### Scenario: a document and its rendering, one above the other

- **Given** a `.md` open in Split Down
- **When** the project is opened again
- **Then** the tab is in Split Down

### Requirement: A split comes back with its divider where it was left

A split SHALL come back with its divider where it was left.

The divider is remembered with the mode, as a fraction of the pane rather than a
position — the pane is not the size it was in another window, on another screen,
or beside a sidebar somebody has since dragged. A split restored to an equal
half is not the tab somebody left, so the fraction travels with the mode.

A tab that is not the one in front has no geometry at all until it is clicked,
so the fraction is held until the split has been laid out with room for both
halves, and applied then.

#### Scenario: a divider three quarters of the way across

- **Given** a `.scad` in Split Right with the source taking three quarters of
  the pane
- **When** another project is opened and then that one again
- **Then** the source still takes three quarters of the pane

#### Scenario: a split behind the tab in front

- **Given** two files restored together, the split one behind the other
- **When** its tab is clicked for the first time
- **Then** its divider is where it was left, not at the half it never had

### Requirement: A session that says nothing about a mode gets the file kind's default

A session that says nothing about a mode SHALL get the file kind's default.

A session written before modes were recorded, or by anything that does not write
them, has no opinion about how a file was being shown — and no opinion means the
default for that kind of file, not the source. A picture opens as the picture, a
PlantUML or Mermaid file opens as both halves, and a Markdown file opens as text,
exactly as each does when it is opened for the first time.

#### Scenario: a session from before the mode was recorded

- **Given** a session file listing a `.mmd` and a `.scad` with no mode against
  either
- **When** the project is opened
- **Then** the `.mmd` is in Split Right and the `.scad` is its source

### Requirement: A mode is ignored for a file that cannot be shown in it

A mode SHALL be ignored for a file that cannot be shown in it.

A mode is only meaningful where there is something to show. A session may name
one against a file that has no rendered form, or one that has no source half to
put beside it — a file renamed, or a session written by hand — and the file kind
decides instead of the note.

#### Scenario: a split written against a file with no preview

- **Given** a session naming Split Right against a `.swift`
- **When** the project is opened
- **Then** the tab is its source, and no split is made

#### Scenario: a split written against a document with no source half

- **Given** a session naming Split Right against a `.drawio`, whose own editor
  owns the document
- **When** the project is opened
- **Then** the tab is the draw.io editor, filling the pane

### Requirement: A driven run neither restores a session nor writes one

A driven run SHALL neither restore a session nor write one.

A session is what a person left behind, and a run being driven from the command
line is not that person. So a run given a launch verb opens the files it was
given and no others, starts no terminal the session had, attaches to no tmux
session the project remembers, and writes nothing back when it ends.

This is the half of it that matters most, because what is on screen is what a
driven verb types into. A window that had restored somebody's tabs and somebody's
shell is a window where `--type` reaches a source file nobody was editing and a
keystroke reaches a shell somebody is standing in — which is what happened, and
what three separate items were filed about before the cause was found.

Nothing about how a session is written or read otherwise changes: the same file,
beside the same project, restored the same way for anybody opening it themselves.

#### Scenario: a typing verb against a project with tabs to restore

- **Given** a project whose session names an open file
- **When** a run with a launch verb opens that project
- **Then** the file is not opened, and the session file on disk is unchanged

#### Scenario: what a driven run leaves in the project

- **Given** a driven run that opens a project, opens files in it, and ends
- **Then** the project's session file says what it said before the run

#### Scenario: somebody opening the project themselves

- **Given** the same project opened with no launch verb
- **Then** the session is restored and written exactly as it always was

### Requirement: A folder that is not a project has one session, kept away from it

A folder that is in no working copy SHALL share one session with every other
such folder, and SHALL have nothing written into it.

The Purpose above says a session is kept beside the project, so that it belongs
to the project rather than to the application. A folder somebody walked into is
not a project and that reasoning does not reach it: there is nothing there to own
a session, and writing one anyway would leave a `.abydos` folder in every
directory a shell has ever passed through — which is a session file per `cd`,
scattered across a disk, for folders nobody chose to open.

So one session serves all of them, kept where the application keeps its own
things. This is the shape the scratches already have, where a scratch belongs
either to a project or to nobody in particular.

It holds the open files and nothing else. Terminals, the tmux window and the
chosen run configuration are all answers to "what was this project set up to
do", and a folder is not set up to do anything — a shell in one is a shell
somebody is using, not a shell the folder came with.

#### Scenario: a folder walked into leaves nothing behind

- **Given** a window following its terminal
- **When** the shell moves through three folders that are in no working copy
- **Then** none of the three holds a `.abydos` folder afterwards

#### Scenario: leaving a project for a folder, and going back

- **Given** a window on a checkout, with two files open
- **When** the shell changes directory to a folder in no working copy
- **Then** the checkout's session is written beside the checkout
- **And** the window shows what was last open in a folder like this one
- **When** the shell changes directory back into the checkout
- **Then** the two files are open again

#### Scenario: the session a folder shares carries files and not terminals

- **Given** a window showing a folder in no working copy, with two terminals
  open in the panel
- **When** the window is closed and another is opened on such a folder
- **Then** the files that were open come back
- **And** the terminals do not

### Requirement: A folder that is not a project keeps its files across a move

A window moving between two folders that are in no working copy SHALL keep every
open file open.

Switching project puts away what one project had open and restores what the next
one did, which is right when there are two projects. Between two folders there is
only one session, so the same act would be a tab set torn down and rebuilt to the
same thing — except that a folder has nothing stored for it, so it would be torn
down and rebuilt to *nothing*, and the files somebody was reading would close
because they had walked into the next directory.

The tree, the search and the file index re-point, because where the shell is is
worth showing. Nothing else moves.

#### Scenario: a `cd` deeper into a folder of notes

- **Given** a window showing `notes`, in no working copy, with `todo.md` open
- **When** the shell changes directory to `notes/2026`
- **Then** the tree shows `notes/2026`
- **And** `todo.md` is still open, and still the tab in front

#### Scenario: the tree follows the shell and not the tabs

- **Given** that window, showing `notes/2026`, with files open from two folders
- **When** the tab in front is changed to one from another folder
- **Then** the tree still shows `notes/2026`
