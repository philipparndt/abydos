# Devcontainers

## Purpose

A project that carries a `devcontainer.json` says which toolchain it is worked
on with, and this program takes it at its word: the language servers run inside
that container rather than against whatever happens to be installed on this
machine, so the problems on screen are the problems from the build. It is not
done without asking, it says in the titlebar that it is being done, and it can
be undone, moved to another of the project's containers, or given back to this
machine, from the one place — the pill beside the project's name.

## Requirements

### Requirement: A devcontainer is asked for before it is started

A devcontainer SHALL be asked for before it is started.

A project with a `devcontainer.json` is not put in a container until somebody
says so. The question is asked once per project, at the moment something needs
the container rather than when the project is opened, and it is a toast that
stays until it is answered rather than anything that takes the keyboard.

It offers three answers however many devcontainers the project has: use the
container it names, work on this machine, or not now. It names one because a
button per container is a wall — the answers stack rather than sit in a row,
since a devcontainer's `name` is a whole sentence — and *which* container is
chosen in the titlebar pill's menu instead.

#### Scenario: a project offering two containers

- **Given** a project with `.devcontainer/alpine/devcontainer.json` and
  `.devcontainer/go/devcontainer.json`, and no answer on file
- **When** a file whose language has a server is opened
- **Then** one question appears, with three answers
- **And** the answer that starts a container names the one that would be started

#### Scenario: ten files at once

- **Given** the same project
- **When** ten files the servers care about are opened together
- **Then** one question is asked, not ten

### Requirement: The answer says which container, and is kept per project

The answer SHALL say which container, and SHALL be kept per project.

Saying yes writes down both halves: that the project is worked on in a
container, and which of its containers that is. The container is written down as
the file's path inside the project — `.devcontainer/go/devcontainer.json` — so
it is the same string for everybody who checks the repository out, and a
checkout that moves keeps its answer.

The two declines are kept as they were: "work on this machine" is written down,
"not now" is not, and neither forgets which container the project's is.

#### Scenario: the answer survives the project being closed

- **Given** somebody answered "use the Go one" in a project offering two
- **When** the project is opened again
- **Then** the Go container is started without a question, and the titlebar
  names it

#### Scenario: declining does not forget the choice

- **Given** a project whose servers were moved onto this machine
- **When** the container is asked for again from the pill
- **Then** it is the container that was chosen before, not whichever sorts first

### Requirement: An answer naming a container the project no longer offers is a question again

An answer naming a container the project no longer offers SHALL become a question again.

`devcontainer.json` is committed, so which containers a project offers can
change between one session and the next. An answer naming one that has gone is
not honoured and is not silently transferred to another: the project reads as
one nobody has been asked about, and the question is put again.

#### Scenario: a container renamed by somebody else

- **Given** a stored answer naming `.devcontainer/go/devcontainer.json`
- **And** a checkout in which that folder is now `.devcontainer/tools`
- **When** a file whose language has a server is opened
- **Then** no container is started for it
- **And** the question is asked again

### Requirement: The titlebar says a container is in use, not which one

The titlebar SHALL say that a container is in use, and SHALL NOT say which one.

A project with a `devcontainer.json` has a pill in the titlebar. It shows the
`⬢` the terminal tab in that container wears, and nothing else — not the
container's name, which is a whole sentence and would be most of a titlebar
beside the project, the branch and the subproject. Dimmed, without the hexagon,
it means the project has a container and is not working inside it.

The name is in the pill's tool tip and at the top of its menu, in both states.

#### Scenario: a project working inside its container

- **Given** a container up for this project's language servers
- **When** the titlebar is looked at
- **Then** the pill shows the `⬢`
- **And** hovering it says which container the servers are running in

#### Scenario: a container that would not start

- **Given** a project that said yes to a container whose build failed
- **When** the pill is looked at
- **Then** it is dimmed, and says the container could not be started and that
  the language servers are running on this machine

### Requirement: The pill's menu lists the containers and switches between them

The pill's menu SHALL list the containers and SHALL switch between them.

The menu names the state, then offers every devcontainer the project has. With
none in use each entry starts one. With one in use the entries are which of them
it is, the one in use marked, and choosing another moves the project's language
servers into it: the servers in the container being left are stopped before the
new ones start, and both containers stay running, because there may be a shell
in either.

A project with one container in use has no list — the state line has already
named it.

#### Scenario: switching between two containers

- **Given** a project whose servers are running in the Alpine container
- **When** the Go container is chosen from the pill's menu
- **Then** no language server of this project is left running in the Alpine one
- **And** its servers start in the Go one
- **And** the pill names the Go one

#### Scenario: choosing the container already in use

- **Given** the same project
- **When** the container it is already using is chosen
- **Then** nothing is stopped and nothing is restarted

### Requirement: Bringing a container up is visible where it is slow

Bringing a container up SHALL be visible where it is slow.

A devcontainer being started for the language servers writes what it is doing
into a terminal pane — the steps, and the output of the pull, the build and the
lifecycle commands — and that pane becomes a shell inside the container when it
is up, keeping the scrollback.

Nobody asked for that pane, so it never takes the keyboard, it is not brought to
the front as it is made, and the panel is not opened for it until the start has
gone on long enough to be worth watching. A start too quick to have been watched
takes its pane away again instead of leaving a shell behind.

#### Scenario: a first start that pulls an image and runs a postCreateCommand

- **Given** a project being opened in a container for the first time
- **When** the start is still going after a few seconds
- **Then** the terminal panel opens showing what the build is printing
- **And** the keyboard is still in the editor

#### Scenario: a container that is quick to start

- **Given** an image already on the machine
- **When** the container comes up in a second or two
- **Then** the terminal panel is not opened and no tab is left behind

#### Scenario: a build that fails

- **Given** a `postCreateCommand` that exits non-zero
- **When** it fails
- **Then** everything it printed is in the pane, with the reason under it
- **And** the panel is showing that pane
- **And** the notice raised beside it says where to look rather than repeating
  the build's output
