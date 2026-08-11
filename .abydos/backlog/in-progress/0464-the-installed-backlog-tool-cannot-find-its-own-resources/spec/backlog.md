<!-- What this item changes about `backlog`. Folded into
     .abydos/backlog/spec/backlog.md by `abydos-backlog done`.

     ADDED, MODIFIED and REMOVED. A rename is a REMOVED and an ADDED.
     Write each requirement as it will read in the spec, in the present
     tense — not as a description of the edit.
     The requirements already there, to name exactly:
       The backlog has a button on the left rail
       A card offers the worktree its item is being worked on in
       A project with no backlog is offered one
       An item filed from the pane lands in open
       A card's progress is the worktree's, and says so
       An item says how much longer it has
-->

## ADDED Requirement: `abydos-backlog` works wherever it is run from

The command ships in three places — inside the app at
`Abydos.app/Contents/Resources/bin/`, on the `PATH` after `make install-cli`,
and beside the binaries of a checkout — and every subcommand behaves the same in
all three. In particular it never fails for want of a resource it ships with:
where the app's resource bundles can be found, they are used; where they cannot,
whatever needed them falls back, and nothing aborts.

### Scenario: the copy inside the app picks an item up

- **Given** `Abydos.app/Contents/Resources/bin/abydos-backlog`, whose own
  directory holds no resource bundles
- **When** `start <number>` is run on a ready item
- **Then** the worktree is made, the item moves to `in-progress/`, and the
  configured assistant is started in the worktree

### Scenario: a copy with no resource bundles anywhere near it

- **Given** the command installed by `make install-cli`, in `/usr/local/bin`
- **When** `start <number>` is run
- **Then** it does the same thing, reading its settings without the shipped
  colour schemes rather than failing

## ADDED Requirement: A start that cannot launch an agent says where the work is

Half of `start` cannot be undone: by the time an agent could fail to launch, the
branch exists, the worktree exists, and the item has moved to `in-progress/` in
both checkouts. So the worktree and the branch are printed as soon as they
exist, before anything is asked of the assistant, and an agent that does not
start is followed by the directory to `cd` into and the prompt it would have
been given. An item that looks picked up and is not is the one outcome this
must not have.

### Scenario: no assistant is installed

- **Given** a backlog configured for an assistant that is not on this machine
- **When** `start <number>` is run
- **Then** it prints the branch and the worktree, says nothing was started, and
  prints the directory and the prompt to hand to an agent by hand

### Scenario: the assistant cannot be run

- **Given** a configured assistant whose binary refuses to start
- **When** `start <number>` is run
- **Then** the failure is reported, and the worktree and prompt are printed so
  the item can be picked up by hand
