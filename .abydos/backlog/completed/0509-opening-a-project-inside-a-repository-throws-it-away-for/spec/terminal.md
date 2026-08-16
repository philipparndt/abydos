<!-- What this item changes about `terminal`. Folded into
     .abydos/backlog/spec/terminal.md by `abydos-backlog done`.

     ADDED, MODIFIED and REMOVED. A rename is a REMOVED and an ADDED.
     Write each requirement as it will read in the spec, in the present
     tense — not as a description of the edit.
     The requirements already there, to name exactly:
       A pane does not inherit a tmux socket path that could not exist
       A pane says how large one of its cells is, and says so again when that changes
       A picture placed where there is not room for it makes the room
       A pane shows what a command printed even if the command has already finished
       A pane can be emulated by libghostty-vt instead of by our own emulator
       An engine says what it cannot do, and the missing parts refuse rather than guess
       A picture drawn with unicode placeholders is shown under either engine
       A pane draws at the display's rate while a program keeps up, and does not replay a backlog
       Either engine names the rows that changed, and neither says "all of them" unless they did
       How big a terminal is and how much history it has are cheap questions, and asking them does not copy the screen
-->

## ADDED Requirement: A window follows its terminal out of the project, and nowhere else

A window can be asked to follow its terminal: when the shell in the pane in
front moves to another project, the window changes to that project, keeping
what each had open. What makes that bearable to leave switched on is that
moving *within* a project changes nothing — a `cd` into `Sources` is somebody
going about their work, not somebody leaving.

Within **the project**, which is not the same as within the repository around
it. A project opened at a subdirectory of a checkout — a package inside a
monorepo, one example inside a folder of them — has a repository above it that
answers for every directory in it, including its own. Reading "which repository
is this directory in" as "where has the shell gone" made every such project
throw itself away for the checkout about a second after it was opened, for a
shell that was sitting exactly where it had been put; the tabs somebody had
just opened were replaced by the checkout's own restored session, and nothing
said so.

So the question the window asks is about the project it is on: a directory
inside it is not a move, and only a directory outside it is. A shell that walks
out — `cd ..` into the checkout, or into any other repository — is followed as
it always was, because that is a person navigating rather than the app reading
its own restore back to itself. A directory belonging to no repository at all
leaves the window where it is.

A capture is the one exception and keeps its own rule: while a screenshot is
being taken the window never follows its terminal anywhere, because the picture
is of a project somebody named on the command line and a pane restored into a
different checkout would swap it without complaint.

### Scenario: a project opened at a subdirectory of a checkout

- **Given** a window following its terminal, opened on `checkout/models`
- **And** its terminal is in `checkout/models`, where the window put it
- **When** the terminal reports where it is
- **Then** the window is still on `checkout/models`, with the tabs it opened

### Scenario: a shell moving deeper into the project

- **Given** that window, on `checkout/models`
- **When** the shell changes directory to `checkout/models/Sources`
- **Then** the window is still on `checkout/models`

### Scenario: a shell that really leaves

- **Given** that window, on `checkout/models`
- **When** the shell changes directory to `checkout`
- **Then** the window changes to `checkout` and restores what it had open

### Scenario: a shell in a directory that is in no repository

- **Given** that window, on `checkout/models`
- **When** the shell changes directory to a folder with no repository above it
- **Then** the window is still on `checkout/models`
