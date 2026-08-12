<!-- What this item changes about `version-control`. Folded into
     .abydos/backlog/spec/version-control.md by `abydos-backlog done`.

     ADDED, MODIFIED and REMOVED. A rename is a REMOVED and an ADDED.
     Write each requirement as it will read in the spec, in the present
     tense — not as a description of the edit.
     The requirements already there, to name exactly:
       The working copy is shown as the folders it changed
       Staging a folder stages everything under it
       A folder says how much of it is on this side of the index
       The commit view keeps its place while files are written
-->

## ADDED Requirement: One question answers which branch the work tree is on

Everything that needs the branch — the titlebar, the branch menu, the project
switcher, the push button — asks `GitRepository.head(in:)`, and it answers in
three states rather than two: a branch, a branch with nothing committed on it,
and no branch at all.

It asks git `symbolic-ref --short HEAD`, which reads the reference HEAD points
at. `rev-parse --abbrev-ref HEAD` is the obvious question and the wrong one: it
resolves the commit and only then names it, so in a repository that has been
created and not yet committed to it fails outright, while the branch name is
sitting in `.git/HEAD`. `branch --show-current` would answer the same thing, but
it is porcelain, it needs git 2.22, and it prints an empty line where
`symbolic-ref` exits non-zero.

A detached HEAD is not a branch and has no name. `symbolic-ref` fails there,
which is how it is told apart — the old question answered the literal string
`HEAD`, and each caller separately had to know to discard it.

### Scenario: a repository with nothing committed yet

- **Given** a repository created with `git init -b main` and no commit made
- **When** the branch is asked for
- **Then** it is `main`, and it is known to have nothing on it

### Scenario: a commit checked out directly

- **Given** the work tree is on a detached HEAD
- **When** the branch is asked for
- **Then** there is no branch name

## ADDED Requirement: A branch with no commits on it shows, quietly

The titlebar names the branch of a repository that has nothing committed to it,
because the name is a fact from the moment `git init` runs, and showing nothing
made a real repository look like a folder that was not one.

It shows dimmed, in the weight the keyboard hint beside it is drawn in, and the
tooltip says why. The name at full weight would read as an ordinary branch, and
on this one the commit page, the push button and the branch menu each behave
differently.

The branch menu opens on such a repository and names the branch, ticked and not
selectable. `git branch` lists refs and an unborn branch has none, so it appears
in no list git can produce — and a menu that refused to open would leave the
places this repository can be opened, on the host and in Fork, unreachable.

### Scenario: the titlebar of a freshly created repository

- **Given** a project whose repository has no commits
- **When** the window opens
- **Then** the titlebar reads the branch's name, dimmed
- **And** its tooltip says there are no commits yet

## ADDED Requirement: Push says which branch it cannot send

A branch with nothing committed on it cannot be pushed — there is no ref to
send, and `git push -u origin main` fails. The button is disabled, and it says
which branch is empty rather than offering the generic "Push this branch" that
a repository with no branch at all gets.

Amending is off for the same reason and is spelt out the same way: there has to
be a commit to amend, and the checkbox is disabled with a tooltip saying so
rather than letting git's `fatal: You have nothing to amend` reach the screen.

### Scenario: a repository with a remote and no commits

- **Given** a repository with an `origin` and nothing committed
- **When** the commit page is opened
- **Then** the push button is disabled and reads `Push`
- **And** its tooltip names the branch and says it has no commits yet
- **And** the Amend checkbox is disabled
