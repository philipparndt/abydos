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

### Requirement: A message being composed survives leaving the project

A project's session SHALL carry the commit message being composed — the summary
and the description both — and SHALL put it back when the project is returned to.

It SHALL be put back wherever the message is composed: the sidebar's changes
pane or the commit page, whichever the returning window builds. It SHALL be put
back where the field is empty and SHALL NOT overwrite anything typed since —
what somebody has just typed is the more recent statement, which is the rule
drafting already follows.

Restoring SHALL survive the sidebar tool being rebuilt when the repository
finishes loading, which happens a second or two after a window opens and is a
second door onto the same loss: the code that rebuilds it already records having
taken "the commit message half typed into the pane" with it.

A commit message is the most expensive text in the app to lose. It is written
once, from a diff somebody has just read, and typing it again means reading the
diff again. The description is the half that says *why* and the half that is
expensive, so carrying only the summary is not carrying the message.

#### Scenario: switching away mid-message

- **GIVEN** a summary and a description typed and not committed
- **WHEN** another project is opened and the first returned to
- **THEN** both fields hold what was typed

#### Scenario: the repository finishes loading underneath

- **GIVEN** a message typed into the changes pane
- **WHEN** reading the repository rebuilds the sidebar tool
- **THEN** the message is still there

#### Scenario: something typed since

- **GIVEN** a session holding a message, and a summary typed into the returning
  pane before the restore lands
- **THEN** what was typed stands, and the session's message does not replace it

#### Scenario: a committed message

- **GIVEN** a message that has been committed and the fields cleared
- **WHEN** the project is left and returned to
- **THEN** the fields are empty

### Requirement: The pages a window had are part of its session

A project's session SHALL carry the pages that were open — commit, log, stash,
and the pages whose identity is their identifier alone — and SHALL reopen them
when the project is returned to.

A page was excluded from a session on the argument that "a path like
`/ideai/page/launch` is nothing to reopen". That is true of the synthetic URL and
false of the page: it is a view over a repository with a scope and a selection,
and it was opened on purpose.

A page SHALL be reopened only once the repository is ready. Every opener refuses
while the project's git is still unread, so reopening earlier would drop the
restore silently.

A session that says nothing about pages SHALL open none: a project opened for the
first time behaves as it did before this requirement.

#### Scenario: pages open at the switch

- **GIVEN** a log page and a commit page open
- **WHEN** another project is opened and the first returned to
- **THEN** both pages are open again

#### Scenario: a project with no recorded pages

- **GIVEN** a project whose session names no pages
- **THEN** no page is opened

### Requirement: A tree comes back folded as it was left

A project's session SHALL carry what was folded and what was unfolded in each of
its trees — the refs tree, the changes tree and the project tree — and SHALL put
it back when the project is returned to.

It SHALL be put back wherever the tree is built, not once after the project is
loaded. A pane is rebuilt several times within one sitting: on a project switch,
a second or two after a window opens when reading the repository lands on a
different work tree, and when a tool shown over the terminal is put away. A
single application after the load is undone by the first of those, which is the
loss the code that rebuilds the sidebar already records having caused — *"it
took with it the commit message half typed into the pane and the folders
unfolded in it"*.

Both records SHALL travel: what was shut, and what was opened. A tree of your
own branches arrives open unless something was shut; the sections that are
somebody else's account of things — a remote, the tags — and the untracked
directories that cost a git call to open arrive shut unless something was
opened. One list of expanded rows cannot say which rule a missing row is under.

A key that names nothing when the tree is built SHALL do nothing, and SHALL NOT
be written down again — a branch deleted, a folder renamed, a stash popped.

What is remembered SHALL be bounded: at most 500 keys per tree, the ones nearest
the root kept. A fold near the root is the arrangement somebody made; a fold
twelve levels down is where they happened to end up.

#### Scenario: the working copy, unfolded

- **GIVEN** a project whose refs tree has the working copy unfolded
- **WHEN** another project is opened and the first returned to
- **THEN** the working copy is unfolded, with its changed files under it

#### Scenario: the repository finishes loading underneath

- **GIVEN** a window whose refs tree has `origin` opened
- **WHEN** reading the repository rebuilds the sidebar tool
- **THEN** `origin` is still open

#### Scenario: a project nobody has folded anything in

- **GIVEN** a project whose session records no folds
- **WHEN** its refs tree is built
- **THEN** the working copy is shut, `origin` and `Tags` are shut, and every
  other section is open — exactly as they are today

#### Scenario: the project tree

- **GIVEN** three folders unfolded in the project tree
- **WHEN** the project is left and returned to
- **THEN** the same three are unfolded, and nothing else is

#### Scenario: a folder that has gone

- **GIVEN** a session naming a folder that has since been deleted
- **THEN** the tree is built without it and nothing is reported

### Requirement: The sidebar tool that was in front comes back

A project's session SHALL carry which sidebar tool was in front, and SHALL show
that tool when the project is returned to.

Where the remembered tool cannot be built — the git tool for a folder in no
working copy, or a tool a later version wrote down — the project tree SHALL be
shown instead of nothing.

Restoring a tool SHALL NOT open a sidebar that was closed. Whether the sidebar
is showing belongs to the window's layout, which is remembered per machine in
the split view's own record; somebody who closed the sidebar closed it for the
window and not for the project.

#### Scenario: a window that lived in the git tool

- **GIVEN** a project left with the refs tree in the sidebar
- **WHEN** it is opened again
- **THEN** the refs tree is the tool in front, and the rail lights its button

#### Scenario: a folder in no working copy

- **GIVEN** a session naming the git tool
- **WHEN** a folder that is in no working copy is shown
- **THEN** the project tree is shown

#### Scenario: a sidebar somebody closed

- **GIVEN** a window whose sidebar is closed
- **WHEN** a project whose session names a tool is opened
- **THEN** the sidebar is still closed

### Requirement: The terminal that was in front comes back in front

A project's session SHALL carry which terminal was in front, by name, and the
panel SHALL bring that one forward when the terminals are restored.

By name and not by index, for the reason the tmux window is an id: a terminal
that fails to start shifts every one after it, and an index then names somebody
else's shell. Where no restored terminal has that name, the panel SHALL do what
it does with a set of terminals today.

#### Scenario: the third of four

- **GIVEN** four terminals with the third in front
- **WHEN** the project is left and returned to
- **THEN** four terminals are open and the third is in front

#### Scenario: a name that did not come back

- **GIVEN** a session naming a terminal in front that no restored terminal is
  called
- **THEN** the terminals open and none is brought forward on account of the note

