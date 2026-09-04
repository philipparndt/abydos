# Sessions — delta

## ADDED Requirements

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
