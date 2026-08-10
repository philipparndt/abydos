## ADDED Requirement: An item's state is the folder it is in

Nothing records a state anywhere else. An item is in `open/`, `ready/`,
`in-progress/`, `waiting/`, `completed/` or `history/`, and moving it along
moves the file or the folder, keeping the number it was given.

### Scenario: moving an item that carries screenshots

- **Given** `open/0443-something/` with `task.md` and two files in `images/`
- **When** it is moved to `ready`
- **Then** it is `ready/0443-something/` with both files still in it
- **And** it still answers to the number 443

### Scenario: a number is given once

- **Given** a backlog whose highest number anywhere, `history/` included, is 442
- **When** a new item is written
- **Then** it is 443, and no existing item's number changes

## ADDED Requirement: An item is a file, or a folder when it carries something

An entry in a state folder is an item if it is a `.md` file, or a directory
containing `task.md`. Both are read the same way: the same title, the same
number, the same checklist.

### Scenario: attaching a file to an item that is one file

- **Given** `open/0443-something.md`
- **When** a screenshot is attached to 443
- **Then** it becomes `open/0443-something/task.md` with the screenshot in
  `images/`, and the markdown is unchanged

### Scenario: two screenshots of the same name

- **Given** an item that already carries `Screenshot.png`
- **When** another file called `Screenshot.png` is attached
- **Then** both are kept, the second as `Screenshot-2.png`

## ADDED Requirement: Ready is the only folder an agent picks from

`ready` means the deciding is done. Nothing moves an item into it
automatically, and picking one up is refused for an item in any other state.

### Scenario: asking for the next thing to do

- **Given** items in `open/` and two in `ready/`, numbered 12 and 8
- **When** the next item is asked for
- **Then** it is 8, and nothing in `open/` is offered

## ADDED Requirement: An item is picked up into a worktree of its own

Starting an item makes a git worktree on `backlog/<number>-<slug>`, moves the
item to `in-progress/` in both the project and the worktree, records the run on
this machine, and starts the configured assistant there.

### Scenario: an item that is not committed

- **Given** a ready item that has never been committed
- **When** it is started
- **Then** it is refused, and stays in `ready/`, because a worktree is a
  checkout of HEAD and would not contain the item

### Scenario: an item already being worked on

- **Given** an item whose worktree exists
- **When** it is started again
- **Then** it is refused and names the worktree

## ADDED Requirement: The spec says what the project does, and items change it by delta

`spec/` holds one file per capability. An item that changes behaviour carries
`spec/<capability>.md` in its own folder, with each requirement headed `ADDED`,
`MODIFIED` or `REMOVED`. Finishing the item folds the delta in.

### Scenario: a delta that no longer fits the spec

- **Given** a delta with `MODIFIED Requirement: X` and a spec with no X
- **When** the delta is checked
- **Then** it says so, naming the capability and the requirement

### Scenario: folding a delta that is partly stale

- **Given** a delta whose first entry cannot be applied and whose second can
- **When** it is folded
- **Then** the second is applied, the first is reported, and the item still
  completes

## ADDED Requirement: Every item tracks what is done and what is missing

An item carries a `## Steps` checklist. `- [x]` is a step that is done and
`- [ ]` is one that is not, and the count is read from the markdown rather than
stored beside it.

### Scenario: an item part way through

- **Given** an item with two ticked steps and two unticked
- **When** it is shown, listed, or drawn on the board
- **Then** it reads `2/4`, and the board draws a bar half filled

### Scenario: finishing with steps left unticked

- **Given** an item with two unticked steps
- **When** it is completed
- **Then** both are printed by name before the move

## ADDED Requirement: A project is set up for its assistants by one command

`abydos-backlog init` makes the folders, writes the workflow document, and
writes the instruction file each chosen assistant reads. It is safe to run
again: files that belong to the project are left as they are, and a file the
project already had keeps everything outside our fenced section.

### Scenario: running init twice

- **Given** a project set up for Claude Code, whose README has been edited
- **When** init is run again for opencode
- **Then** both assistants are configured, the edited README is untouched, and
  the workflow document is brought up to date

### Scenario: instruction files the repository ignores

- **Given** a project whose `.gitignore` covers where an assistant's file goes
- **When** init writes it
- **Then** it says which files nobody who clones will get
