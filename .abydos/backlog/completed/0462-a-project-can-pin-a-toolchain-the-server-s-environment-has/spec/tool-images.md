## ADDED Requirement: A project pinning a toolchain the image has not got is told before anything starts

An image fixes its toolchain when the image is *built*; a project pins its
toolchain when the project is *opened*. Nothing reconciles the two, and where
they disagree the server starts, answers the handshake and then refuses every
question about every file — a shape that reads as the editor being broken.

The pin, though, is a file in the project, so it is read first: before a server
is started, before an image is fetched, and while the choice of where the tool
comes from is still somebody's to make. What is found is said above the file and
in the settings page where that choice is offered.

Only a pin nothing can answer is said, and which those are is a judgement rather
than a list. A pinned *release* reconciles itself — the toolchain installer in
the image fetches a release it has not got — and saying anything about it would
put a strip over every pinned project on the machine, which is how a strip stops
being read. A *custom* channel, a name that means a directory somebody's
installer left on one machine, is in no image and never will be. Whether the
copy installed on this machine answers it is not assumed either way: it is read
off that machine, because the one route a custom channel can take is the one
that is not an image, and it is not always open.

What is said names every place the tool could come from and what each does with
this pin, including the ones not in use. The question it raises is what to do
instead, and where the answer is "none of them" that is worth saying outright
rather than leaving somebody to find it out one setting at a time.

### Scenario: a custom channel and an image

- **Given** a project whose `rust-toolchain.toml` says `channel = "esp"`
- **And** rust-analyzer coming from an image
- **When** a Rust file in it is opened
- **Then** the strip above the file says that channel is in no image, before the
  server has been asked anything
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

### Scenario: a custom channel nothing can answer

- **Given** the same project
- **And** a toolchain of that name installed here without the server in it
- **When** the tool is taken from the copy installed on this machine
- **Then** it says that copy has no such server, rather than offering it as the
  way out

## MODIFIED Requirement: Every language server this editor offers has an image this repository builds

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
