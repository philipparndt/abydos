## ADDED Requirements

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
