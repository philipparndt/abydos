# Tool images

## Requirement: A tool can come from an image, and the project's choice wins

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

## Requirement: An image that is not here is fetched before the tool is first used

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

## Requirement: A server in a container talks about files by their names on this machine

A language server started from an image sees the project at a mount inside the
container and knows no other name for it. Everything it is sent names files as
this machine names them, everything it says names them the same way, and the
translation happens at the edge of the client in both directions — for the URIs
that are values and for the ones that are keys, so that a workspace edit's map of
changes crosses too.

A path the container cannot see is refused rather than guessed at: inventing a
name inside a mount would point the server at the wrong file rather than at
none. Where a server has named directories beyond the project, those are the
other things it can see, and a file in one of them crosses in both directions
exactly as a file in the project does. Everything else is still refused, which
is the same rule over a longer list rather than a weaker one.

### Scenario: a diagnostic about an open file

- **Given** a project mounted at `/workspace` in a container
- **When** the server reports a problem in `file:///workspace/main.go`
- **Then** it is reported against the file's path on this machine

### Scenario: going to a declaration

- **Given** the same project, and a call to a function declared in the same file
- **When** the declaration is asked for
- **Then** the place that comes back is a file on this machine

### Scenario: a declaration in a directory the server named

- **Given** a server given a dependency cache from this machine beside the
  project
- **When** it answers with a file in that cache
- **Then** the place that comes back is that file's path on this machine

### Scenario: a file in neither

- **Given** the same server
- **When** it is asked about a file that is in neither the project nor anything
  it named
- **Then** nothing is translated, and the server is told about no such file

### Scenario: a rename crossing in both directions

- **Given** a project in a container, and a symbol used in two of its files
- **When** it is renamed
- **Then** every file the answer names is a file on this machine
- **And** both are changed

## Requirement: A published image is only offered once somebody has run it

The published images offered for a tool are the ones that have been built,
pushed, fetched back out of the registry and driven against a real project.
Listing one nobody has run would be exactly the failure the list exists to
prevent — a name offered as known-good that is not — so a tool nobody has done
that for offers no published image at all. It may still offer the recipe this
app ships, which is a different claim: that is a build, and what it produces is
whatever the Dockerfile says today.

Beside the choice, for whoever names their own, is what an image has to do: the
tool on the entry point so that it is what runs, speaking the protocol on
standard input and output with nothing printed before the first header, the
project readable at the mount, and everything else it needs inside the image,
because nothing else on this machine is visible from in there — save the
directories that server has named, which are mounted where it says they go, and
which an image that looks elsewhere for will find empty without saying so.

Where an offered image carries a tag that moves, the label says so, since a
list of images known to work is a claim with a date on it when the name is
mutable.

### Scenario: a server nobody has published an image for

- **Given** a language server this editor knows about and has no known-good
  published image for
- **When** its image is chosen in settings
- **Then** no published image is among the choices

### Scenario: an image named by hand

- **Given** a tool whose image is a name somebody typed
- **When** that tool's settings are looked at
- **Then** what the image has to provide is written there

## Requirement: Every language server this editor offers has an image this repository builds

Every language server that can be chosen in the tool settings has a
`ToolImages/<tool>/Dockerfile` in this repository meeting the contract above.
Six of them — gopls, rust-analyzer, pyright, typescript-language-server, clangd
and jdtls — are also published, so each offers a known-good image as well as
the recipe. `make tool-image TOOL=<tool>` builds one for this machine, and
`make toolimage-publish TOOL=<tool>` builds it for every architecture the editor
runs on and pushes a single index.

Each carries the toolchain its server is a front end for, because a language
server without one starts, answers the handshake, and then knows nothing about
any symbol. That toolchain is chosen when the image is built and is not an
argument to the build: an argument would have to go into the fingerprint the
image is named by, or two different images would share one name — and no tool
here has a use for one, since a toolchain a project pins is either a release the
image fetches for itself or a channel that cannot be built from anywhere.

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

## Requirement: A tool can be built here from a recipe Abydos ships

A tool that comes from a container image can come from an image published
somewhere, from an image somebody names themselves, or from a Dockerfile that
travels with Abydos and is built on the machine that wants it. The third sits
beside the other two rather than replacing either: a tool whose build is
genuinely expensive keeps its published image, and a tool that both publishes an
image and ships a Dockerfile offers both.

A project asks for it by writing `build` where an image name would go, and the
same word is what a settings page stores. The name of the image that is actually
built is not written down anywhere, because it carries a fingerprint of the
recipe and is worked out at the moment it is used.

### Scenario: a project asks for a tool to be built here

- **Given** `ToolImages/openscad-lsp/Dockerfile` ships with Abydos
- **And** a project whose `.abydos/tools.json` says `{"openscad-lsp": "build"}`
- **When** a `.scad` in that project is opened
- **Then** the language server is started from an image built on this machine,
  with the project mounted at `/workspace`

### Scenario: a tool with no recipe is asked to be built here

- **Given** a project whose `.abydos/tools.json` asks for `jdtls` to be built
- **And** Abydos ships no Dockerfile for `jdtls`
- **When** a Java file in that project is opened
- **Then** the copy installed on this machine is used, and no container is
  started from a name Abydos invented

## Requirement: An edited recipe rebuilds and an unedited one never does

The image built from a recipe is named after the recipe: `abydos-built/<tool>`
tagged with a digest of everything in the build context. So the first use of a
tool is a build and every use afterwards is not, and editing the Dockerfile —
or anything else in its directory — is what makes the next use a build again.

The digest covers the whole context rather than the Dockerfile alone, and takes
each file's path relative to that context, so the copy of the recipe inside the
`.app` and the copy in a checkout name the same image.

### Scenario: the recipe has not changed

- **Given** a tool that has been built here once
- **When** it is used again
- **Then** nothing is built and the image already on the machine is used

### Scenario: the recipe has changed

- **Given** a tool that has been built here once
- **And** a file in its build context has since been edited
- **When** it is used again
- **Then** a new image is built, under a name that differs from the old one

## Requirement: Nothing built here is ever fetched from a registry

An image name in `abydos-built/` says the image is made rather than pulled, and
that is the only thing that decides which happens: no registry has anything
under that name, so a name in it is never sent to one. Everything else — a
published image, one somebody named — is fetched exactly as before.

What is said while it happens says which of the two it is. A build is minutes
where a pull is seconds, and somebody told "fetching" during a build concludes
their network is broken.

### Scenario: an image this app makes is not on the machine

- **Given** a tool asking for an image built here that is not on the machine
- **When** it is needed
- **Then** the runtime is asked to build it from the recipe, and nothing is
  pulled

## Requirement: A build that fails says which kind of failure it was

A build can fail in ways a pull cannot: the base image has to be fetched, a
compiler has to work, and a package index has to be reachable. Each has a
different answer, so what is reported is one sentence naming which — the runtime
is not running, the network was not there, the registry refused the base image,
there was no room — rather than the runtime's own build log.

Anything else is the recipe itself failing, and the sentence then says where the
Dockerfile is: unlike a published image, it is a file the person reading the
message can open and change.

The log is not thrown away with it. Everything the build printed stays in the
tab it was being written into, the sentence goes last and in red, and the panel
is opened at once so it can be read — a failure is the one outcome that has to
be seen. The sentence is said in the corner as well, and that is not a summary
of the log: four of the five answers are a diagnosis and somebody who reads
"there was no room" is finished. The tab is for the fifth, where the answer is
one line somewhere in a hundred of compiler output.

### Scenario: there is no network

- **Given** a tool that has to be built here
- **And** a machine that cannot reach the registry the base image comes from
- **When** the build is attempted
- **Then** it is reported as the network not being there, naming the recipe,
  and not as the tool being broken

### Scenario: the recipe's own build fails

- **Given** a tool whose Dockerfile has a step that returns non-zero
- **When** it is built on this machine
- **Then** everything the build printed is in the terminal panel with the
  reason last
- **And** what is said in the corner names that tab

## Requirement: A server may say it reads directories the project does not contain

Almost every language server is answered by the project alone, and is given the
project alone. One is not: a server with no classpath finds a library's source
by walking the caches a build tool left behind — `~/.m2/repository` and
`~/.gradle/caches` — so the same server in a container with one mount indexes
the project perfectly and answers nothing at every dependency boundary.

So a server may name the directories it reads outside the project, and they are
mounted for it. It is a list per server rather than a rule for all of them,
because what one reads is a fact about that server: another server's cache is a
saving where this one's is the answer, and one that resolves its dependencies by
running a build tool is hindered by being handed a read-only copy of them.

What is mounted is what was named — a cache, not the directory above it that
holds the credentials — and it is read-only unless the server writes there. The
writable case is a server's own scratch, and it is mounted precisely because
what it writes there has to be readable from this side: a file unpacked out of a
jar inside the container and named back to the editor would be an answer that
opens nothing.

A directory that is not on this machine is an ordinary machine and not a broken
one. A read-only one that is missing is not mounted, and the server then
truthfully reports no dependencies; a writable one is created, since it is the
server's scratch rather than somebody's cache.

### Scenario: a dependency's source in the local repository

- **Given** a Java project naming a server that reads `~/.m2/repository`
- **And** a dependency whose source jar is in it
- **When** the declaration of a type from that dependency is asked for
- **Then** the place that comes back is a file this machine can open

### Scenario: a machine that has never run that build tool

- **Given** the same project on a machine with no `~/.m2`
- **When** the server is started
- **Then** it starts, with no repository mounted and none created

### Scenario: what a server may do to a cache

- **Given** a server given a dependency cache from this machine
- **When** it runs
- **Then** it can read it and cannot write to it

## Requirement: An image that takes minutes is watched rather than waited for

Getting an image can be a download of a gigabyte or a compiler running for
minutes, and either used to be one sentence in the corner followed by silence.
Silence after a sentence is indistinguishable from a feature that did not work,
which is exactly the conclusion somebody drew.

So a fetch or a build that is not answered at once opens a terminal tab of its
own and writes the runtime's own output into it as it arrives. The terms are the
ones a devcontainer coming up already has, because it is the same wait for the
same reason: the tab never takes the keyboard, since whoever started this was
doing something else; the panel is opened only if the work is still going after
three seconds; and work quick enough that nobody could have watched it takes its
tab away again rather than leaving one behind. An image already on the machine —
which is every use after the first — makes no tab at all, because nothing is
said and there is nothing to watch.

The tab says which of the two is happening, since a build is minutes where a
fetch is seconds, and it says it in the place somebody reads before opening
anything.

A pane that is only ever a report is not remembered as one of the project's
terminals. Everything in the panel is written into the session and opened again
next time; a build's pane never becomes a shell, so remembering it would give
somebody a prompt named after a build every time they opened the project.

### Scenario: a tool built here for the first time

- **Given** a project asking for a language server to be built on this machine
- **And** that image is not here yet
- **When** a file of that language is opened
- **Then** a tab named for the build holds what the runtime prints while it runs
- **And** the panel opens by itself once the build has gone on for three seconds
- **And** the keyboard stays where it was

### Scenario: the image is already on the machine

- **Given** the same project, with that image already built
- **When** a file of that language is opened
- **Then** no tab is opened and nothing is said

### Scenario: something quick enough that nobody could have watched it

- **Given** an image that arrives in less than three seconds
- **When** something needs it
- **Then** the tab it was being written into goes with it

### Scenario: the project is opened again afterwards

- **Given** a build whose tab was left open and read
- **When** the project is closed and opened again
- **Then** there is no tab where it was, and no shell named after a build

## Requirement: A project pinning a toolchain the image has not got is told before anything starts

An image fixes its toolchain when the image is *built*; a project pins its
toolchain when the project is *opened*. Nothing reconciles the two, and where
they disagree the server starts, answers the handshake and then refuses every
question about every file — a shape that reads as the editor being broken.

The pin, though, is a file in the project, so it is read first: before a server
is started, before an image is fetched, and while the choice of where the tool
comes from is still somebody's to make. What is found is said above the file and
in the settings page where that choice is offered.

Only a pin nothing has answered is said, and which those are is a judgement
rather than a list. A pinned *release* reconciles itself — the toolchain
installer in the image fetches a release it has not got — and saying anything
about it would put a strip over every pinned project on the machine, which is how
a strip stops being read. A *custom* channel, a name that means a directory
somebody's installer left on one machine, is in no ordinary image and never will
be.

**What the pin decides, and what it does not.** It decides which compiler and
which build tool read the project, which is the whole point of pinning. It does
not decide which *language server* runs: the server is an ordinary program that
shells out to the pinned toolchain, so any recent one reads the project. What
stops it is being reached by *name*, because the name on the path belongs to the
toolchain manager, which resolves the pin and refuses to hand over a server the
pinned toolchain has not got. So a pin that has been answered by naming an
executable is not said at all, and neither is one coming from a recipe this
repository ships *for that channel* — a recipe here is this project's own answer,
and warning about it would be warning about ourselves.

What is said names every place the tool could come from and what each does with
this pin, including the ones not in use, and then says what to do. Where a server
exists elsewhere on this machine it is named, with the line to write down; where
none does, what to install and where to name it. The question somebody has on
reading a strip is what to do instead, and it always has an answer.

### Scenario: a custom channel and an image

- **Given** a project whose `rust-toolchain.toml` says `channel = "esp"`
- **And** rust-analyzer coming from an image
- **When** a Rust file in it is opened
- **Then** the strip above the file says that channel is in no ordinary image,
  before the server has been asked anything
- **And** its details name the installed copy and the recipe as well, and say
  what each of them does with this pin

### Scenario: a pin one directory down

- **Given** a repository whose root holds no Rust, with the pin in `esp32/`
- **When** a Rust file under `esp32/` is opened
- **Then** it is the project's pin, and is read

### Scenario: a pinned release

- **Given** a project whose `rust-toolchain.toml` names `1.90.0`
- **When** a Rust file in it is opened
- **Then** nothing is said, because the image fetches that toolchain itself

### Scenario: a custom channel this machine has the server for

- **Given** a project pinning a custom channel
- **And** a toolchain of that name installed here with the server in it
- **When** the tool is taken from the copy installed on this machine
- **Then** nothing is said

### Scenario: the pinned toolchain has no server and another toolchain does

- **Given** a project pinning a custom channel
- **And** a toolchain of that name installed here without the server in it
- **And** a release toolchain installed here that has the server
- **When** the tool is taken from the copy installed on this machine
- **Then** the strip says the pinned copy has no such server, and names the
  toolchain that does
- **And** its details give the line to write into `.abydos/tools.json`

### Scenario: no toolchain here has the server

- **Given** the same project
- **And** no toolchain here with the server in it
- **When** the tool is taken from the copy installed on this machine
- **Then** it says so, and says what to install and where to name its path

### Scenario: an executable already named for the server

- **Given** a project pinning a custom channel
- **And** an executable named for that server, in the file or in settings
- **When** a file in it is opened
- **Then** nothing is said about the pin, whichever route the tool comes from

## Requirement: A recipe can be asked for that is not the tool's own

A tool usually has one recipe here and `build` is the whole question. Where a
tool has two — because one kind of project needs an image the others should not
pay for — `build:<recipe>` asks for the other one, and everything downstream is
unchanged: the built image is still named for the recipe and its fingerprint, so
an edited recipe still rebuilds and an unedited one still does not.

This is a project's choice and not a person's. A second recipe exists for a
property of a project, so it is asked for in the project's file and is not offered
in settings, where choosing it would choose it for every project opened.

### Scenario: a project asking for the other recipe

- **Given** two recipes for one tool
- **When** a project asks for `build:<the other one>`
- **Then** that recipe is what gets built, under its own name
- **And** an edit to it rebuilds, as an edit to the tool's own recipe does

### Scenario: asking for a recipe nobody ships

- **When** a project asks for `build:<a name with no recipe>`
- **Then** there is no image, and the copy installed on this machine is used —
  the same answer as naming an image nothing can run

## Requirement: A container an earlier run left behind is removed by the next one, in whichever runtime holds it

Every container Abydos starts is named `abydos-<role>-<pid>-<n>`, and the process
id in that name is what makes one found tomorrow answerable: it is stale exactly
when the process that started it is gone. Starting up, Abydos removes the stale
ones and leaves the rest alone, so two copies open at once — or a copy open beside
a test run — never take each other's.

**Every runtime installed is asked, not the preferred one.** A leftover is in
whichever runtime started it, and that need not be the one anybody would choose
today: a machine with the docker command line installed and its daemon stopped
prefers docker, whose listing fails, while every container actually left behind
sits in Apple's runtime where nothing looked. What is said afterwards names the
runtime as well as the containers, because which of the two was holding them is
the next question anybody reading the line asks.

Nothing is ever reused. A container is started under a name minted for that
launch, so a name is never asked for twice, and a runtime asked for one that
exists refuses it rather than handing back what is there.

### Scenario: a container whose owner is gone

- **Given** `abydos-lsp-jdtls-75631-23` in Apple's runtime
- **And** no process 75631 on this machine
- **When** Abydos starts
- **Then** the container is removed
- **And** what is said names the runtime it was removed from

### Scenario: the preferred runtime is not the one holding it

- **Given** the same container in Apple's runtime
- **And** the docker command line installed with its daemon stopped, which is the
  preferred runtime
- **When** Abydos starts
- **Then** the container is still removed

### Scenario: a container somebody is using

- **Given** `abydos-lsp-rust-analyzer-84402-1` and a process 84402 still running
- **When** Abydos starts
- **Then** the container is left alone

### Scenario: a name that is already taken

- **Given** a container of ours still on the machine
- **When** a tool is started
- **Then** it is started under a name of its own rather than in the one that is
  there
