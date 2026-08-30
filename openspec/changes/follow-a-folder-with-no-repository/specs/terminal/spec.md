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
its own restore back to itself.

A working copy *inside* the project is the exception, and it is a move: it is a
project of its own, and walking into one is walking somewhere else. Without that
exception `.abydos` sets a trap — a folder opened at the home directory is marked
for ever, so every checkout underneath it counts as inside the project and no
`cd` moves the window again.

**Which project a directory belongs to is decided by `.git`, `.svn`, `.hg` and
`.abydos`.** Git is not the only way somebody keeps their work, and a window
that follows a shell between two checkouts and refuses to follow it into a
Subversion working copy is not obeying a rule anybody would recognise — it
looks broken, and there is nothing said to tell the two apart. `.abydos` counts
because it is this application's own record that somebody deliberately opened
this folder as a project, which is a stronger statement about a directory than
any build file in it. A `.svn` naming a working-copy root is told from one
belonging to an interior directory of an old-layout checkout, the way a
submodule's `.git` is told from a worktree's: by what is inside it.

**A folder in none of those is shown, and is not a project.** The tree, the
search and the file index point at it, so following a shell there is worth
something; it has no branch, no run configuration and no session of its own,
and nothing is written into it. This is what a folder is: somewhere to work on
files, arrived at by walking there rather than by being opened. A folder with
nothing above it used to leave the window where it was, which meant that a
shell in a Subversion working copy or in an ordinary directory of notes moved
the window nowhere and said nothing about why.

**And following into one is a setting of its own, off by default.** Following
between projects moves the window when somebody goes to another piece of work,
and a working copy is what says the walk is over. A folder has no such edge:
with this on, `~/Downloads` and `/tmp` are somewhere to follow to, and every
`cd` anywhere is a move. Two different appetites, so two switches — the second
under the first and meaning nothing without it.

Because such a folder is not a project, moving between two of them is not a
project switch: the tree re-points and **every open file stays open**. There is
nothing per-folder to put away and nothing to restore, so there is nothing to
lose. What they share instead is one session, described by the `sessions`
capability.

A directory that is not there is not followed. A shell can be sitting in a
working directory that has been deleted underneath it, and the path it reports
then names nothing; a window that pointed at it would be showing a root it
cannot read.

**Only while the shell is waiting.** Where a terminal *is* is where its shell
is, and while a command runs that is not where the command has got to. `brew`
changes directory several times over one install; a build script does the same;
reading the foreground process's own answer dragged the window through every one
of them and left it wherever the last happened to be. So the question is asked
only when the shell itself is what the terminal is showing — its process group
in the foreground, which is what `tcgetpgrp` answers with while nothing else is
running, and what tmux says through `pane_current_command`.

Nothing somebody types is lost by this: `cd` is a builtin, so the shell forks
nothing and never leaves the foreground to do one, and the move is followed at
the moment it is made. What is lost is every directory a command wandered
through, which was never a statement about where the terminal was.

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

#### Scenario: a checkout inside the project the window is on

- **Given** a window on a folder somebody opened at their home directory, which
  is therefore marked as a project
- **When** the shell changes directory into a checkout underneath it
- **Then** the window changes to that checkout

#### Scenario: the checkout the project sits in

- **Given** a window on `checkout/models`
- **When** the shell changes directory to `checkout/models/Sources`
- **Then** the window is still on `checkout/models`, because the checkout that
  answers for that directory is above the project and not inside it

#### Scenario: a submodule inside the project

- **Given** a window on a repository with a submodule at `vendor/thing`
- **When** the shell changes directory into the submodule
- **Then** the window does not move, the submodule belonging to the repository
  around it

#### Scenario: a shell in a Subversion working copy

- **Given** a window following its terminal, on some other project
- **And** a Subversion working copy at `wc`, whose `.svn` names it the root
- **When** the shell changes directory to `wc/trunk/src`
- **Then** the window changes to `wc`, and not to `wc/trunk/src`

#### Scenario: a working copy that keeps metadata in every directory

- **Given** a working copy at `wc` made by a client that writes a `.svn` into
  every directory rather than one at the root
- **When** the shell changes directory to `wc/trunk/src`
- **Then** the window changes to `wc`

#### Scenario: a working copy checked out inside another

- **Given** a working copy at `outer` and another at `outer/inner`
- **When** the shell changes directory to `outer/inner/src`
- **Then** the window changes to `outer/inner`, the nearest of the two

#### Scenario: a shell in a directory that is in no repository

- **Given** that window, on `checkout/models`, and following into folders turned
  on
- **When** the shell changes directory to a folder with no `.git`, `.svn`, `.hg`
  or `.abydos` above it
- **Then** the window shows that folder, with its tree and its search
- **And** the folder is not recorded as a recent project
- **And** nothing is written into the folder

#### Scenario: the same, with the setting off

- **Given** that window, on `checkout/models`, and the default settings
- **When** the shell changes directory to a folder that is in no working copy
- **Then** the window is still on `checkout/models`

#### Scenario: a script that changes directory while it runs

- **Given** a window following its terminal
- **When** a command is run that changes directory several times before it ends
- **Then** the window does not move while it runs
- **And** it does not move when it finishes, the shell being where it was

#### Scenario: a `cd` typed at the prompt

- **Given** the same window
- **When** somebody types `cd` into another checkout
- **Then** the window follows, at the moment they press Return

#### Scenario: a shell moving between two such folders

- **Given** following into folders turned on, and a window showing a folder that
  is in no working copy, with three files open
- **When** the shell changes directory to another folder that is in none either
- **Then** the window shows the second folder
- **And** the three files are still open, in the same tabs

#### Scenario: a shell in a folder inside the project the window is on

- **Given** a window on `notes`, a folder somebody opened by hand
- **When** the shell changes directory to `notes/data`
- **Then** the window is still on `notes`, with the tabs it opened

#### Scenario: a pane brought forward carrying a folder as its root

- **Given** a window following its terminal, showing a folder in no working copy
- **And** a pane created while that folder was showing, so the pane's root is it
- **When** that pane is brought forward
- **Then** the folder is shown as a folder and not as a project
- **And** nothing is written into it, and it is not recorded as a recent

#### Scenario: a shell whose working directory has been deleted

- **Given** a window following its terminal
- **When** a pane reports a working directory that no longer exists
- **Then** the window is where it was

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
