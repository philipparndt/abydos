<!-- What this item changes about `tool-images`. Folded into
     .abydos/backlog/spec/tool-images.md by `abydos-backlog done`.

     Nothing had been said about tool-images yet, so this is all ADDED.
-->

## ADDED Requirement: A tool can come from an image, and the project's choice wins

Some of the tools this editor drives are not part of it — a diagram renderer,
and a language server per language — and each is a program somebody would
otherwise install by hand, in the version their project expects, on every
machine they work on. A project may name a container image for a tool in
`.abydos/tools.json` instead, and a person may name one in settings; the
project's answer wins, because naming an image is a statement about what that
project needs and a copy installed on one machine must not quietly change the
answers it gets.

Where nothing is named, whatever is installed on the machine is used. It starts
faster and it is what somebody chose, and an image nothing on the machine can
run is not an answer: with no container runtime installed, the installed copy is
used rather than nothing.

### Scenario: a project and a person name different versions

- **Given** a project whose `.abydos/tools.json` names `plantuml/plantuml:1.2025.4`
- **And** a personal setting naming `plantuml/plantuml`
- **When** a diagram in that project is drawn
- **Then** it is drawn by `plantuml/plantuml:1.2025.4`

### Scenario: a setting the project says nothing about

- **Given** the same project and setting, and a personal setting for `gopls`
- **When** a Go file in that project is opened
- **Then** the `gopls` setting applies

### Scenario: an image nothing can run

- **Given** a project naming an image for a tool
- **And** no container runtime installed
- **When** that tool is used
- **Then** the copy installed on this machine is used instead

## ADDED Requirement: An image that is not here is fetched before the tool is first used

A named image is fetched before the first thing that needs it starts, once
however many things ask for it at the same time, with the image's name on screen
while it happens.

A fetch that fails says which of four things went wrong — the name is wrong,
nobody is signed in to that registry, there is no network, or the runtime is not
running — because each has a different answer and "pull failed" has none.
Anything the runtime says that matches none of the four is passed on as the
runtime said it, rather than given an invented reason.

The runtimes do not share a store. An image pulled by one is invisible to the
other, so a failure that could mean "this is in the other one" asks the other
one, and says so when the answer is yes.

### Scenario: two panes wanting the same image at once

- **Given** an image named by a project and not on this machine
- **When** two things that need it start together
- **Then** it is fetched once, and both wait for that one fetch

### Scenario: the image is in the other runtime's store

- **Given** an image that docker has and Apple's `container` does not
- **And** Apple's runtime preferred
- **When** the tool is used
- **Then** the failure says the image is in docker's store
- **And** offers the runtime choice in settings before offering a fetch

## ADDED Requirement: A server in a container talks about files by their names on this machine

A language server started from an image sees the project at a mount inside the
container and knows no other name for it. Everything it is sent names files as
this machine names them, everything it says names them the same way, and the
translation happens at the edge of the client in both directions — for the URIs
that are values and for the ones that are keys, so that a workspace edit's map
of changes crosses too.

A path outside the project is refused rather than guessed at: the container
cannot see it, and inventing a name inside the mount would point the server at
the wrong file rather than at none.

### Scenario: a diagnostic about an open file

- **Given** a project mounted at `/workspace` in a container
- **When** the server reports a problem in `file:///workspace/main.go`
- **Then** it is reported against the file's path on this machine

### Scenario: going to a declaration

- **Given** the same project, and a call to a function declared in the same file
- **When** the declaration is asked for
- **Then** the place that comes back is a file on this machine

## ADDED Requirement: An image is only offered once somebody has run it

The images offered for a tool are the ones that have been built, published,
fetched back and driven against a real project. Listing one nobody has run would
be exactly the failure the list exists to prevent — a name that is offered as
known-good and is not — so a tool with no such image offers the installed copy
and an image named by hand, and nothing else.

Beside the choice, for whoever names their own, is what an image has to do: the
tool on the entry point so that it is what runs, speaking the protocol on
standard input and output with nothing printed before the first header, the
project readable at the mount, and everything else it needs inside the image,
because nothing on this machine is visible from in there.

Where an offered image carries a tag that moves, the label says so, since a
list of images known to work is a claim with a date on it when the name is
mutable.

### Scenario: a server nobody has published an image for

- **Given** a language server this editor knows about and has no known-good image for
- **When** its image is chosen in settings
- **Then** the choices are the installed copy and a custom image, and no more

### Scenario: an image named by hand

- **Given** a tool whose image is a name somebody typed
- **When** that tool's settings are looked at
- **Then** what the image has to provide is written there

## ADDED Requirement: Every language server this editor offers has an image this repository builds

For each of the six language servers that can be chosen in the tool settings —
gopls, rust-analyzer, pyright, typescript-language-server, clangd and jdtls —
this repository holds a `ToolImages/<tool>/Dockerfile` meeting the contract
above. `make tool-image TOOL=<tool>` builds one for this machine, and
`make toolimage-publish TOOL=<tool>` builds it for every architecture the editor
runs on and pushes a single index.

Each carries the toolchain its server is a front end for, because a language
server without one starts, answers the handshake, and then knows nothing about
any symbol.

### Scenario: building one by name

- **Given** a checkout of this repository and a container runtime
- **When** `make tool-image TOOL=clangd` is run
- **Then** an image is built that a project can name for `clangd`

### Scenario: a server driven from its image

- **Given** an image for one of the six on this machine
- **And** a project of that language naming it in `.abydos/tools.json`
- **When** a file in that project is opened
- **Then** the server answers with that file's symbols and declarations,
  named as this machine names them
