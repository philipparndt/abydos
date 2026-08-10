<!-- What this item changes about `tool-images`. Folded into
     .abydos/backlog/spec/tool-images.md by `abydos-backlog done`.

     ADDED, MODIFIED and REMOVED. A rename is a REMOVED and an ADDED.
     Write each requirement as it will read in the spec, in the present
     tense — not as a description of the edit.
     Nothing has been said about tool-images yet, so this is all ADDED.
-->

## ADDED Requirement: A tool can be built here from a recipe Abydos ships

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

## ADDED Requirement: An edited recipe rebuilds and an unedited one never does

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

## ADDED Requirement: Nothing built here is ever fetched from a registry

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

## ADDED Requirement: A build that fails says which kind of failure it was

A build can fail in ways a pull cannot: the base image has to be fetched, a
compiler has to work, and a package index has to be reachable. Each has a
different answer, so what is reported is one sentence naming which — the runtime
is not running, the network was not there, the registry refused the base image,
there was no room — rather than the runtime's own build log.

Anything else is the recipe itself failing, and the sentence then says where the
Dockerfile is: unlike a published image, it is a file the person reading the
message can open and change.

### Scenario: there is no network

- **Given** a tool that has to be built here
- **And** a machine that cannot reach the registry the base image comes from
- **When** the build is attempted
- **Then** it is reported as the network not being there, naming the recipe,
  and not as the tool being broken
