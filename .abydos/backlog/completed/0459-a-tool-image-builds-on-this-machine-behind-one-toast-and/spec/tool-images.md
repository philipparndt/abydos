## ADDED Requirement: An image that takes minutes is watched rather than waited for

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

## MODIFIED Requirement: A build that fails says which kind of failure it was

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
