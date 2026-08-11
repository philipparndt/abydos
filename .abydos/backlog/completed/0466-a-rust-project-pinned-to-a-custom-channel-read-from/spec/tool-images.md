## MODIFIED Requirement: A project pinning a toolchain the image has not got is told before anything starts

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

## ADDED Requirement: A recipe can be asked for that is not the tool's own

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
