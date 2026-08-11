<!-- What this item changes about `tool-images`. Folded into
     .abydos/backlog/spec/tool-images.md by `abydos-backlog done`.

     ADDED, MODIFIED and REMOVED. A rename is a REMOVED and an ADDED.
     Write each requirement as it will read in the spec, in the present
     tense — not as a description of the edit.
     The requirements already there, to name exactly:
       A tool can come from an image, and the project's choice wins
       An image that is not here is fetched before the tool is first used
       A server in a container talks about files by their names on this machine
       A published image is only offered once somebody has run it
       Every language server this editor offers has an image this repository builds
       A tool can be built here from a recipe Abydos ships
       An edited recipe rebuilds and an unedited one never does
       Nothing built here is ever fetched from a registry
       A build that fails says which kind of failure it was
       A server may say it reads directories the project does not contain
       An image that takes minutes is watched rather than waited for
       A project pinning a toolchain the image has not got is told before anything starts
       A recipe can be asked for that is not the tool's own
-->

## ADDED Requirement: A container an earlier run left behind is removed by the next one, in whichever runtime holds it

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
