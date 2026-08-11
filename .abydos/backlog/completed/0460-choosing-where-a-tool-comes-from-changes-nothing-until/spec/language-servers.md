<!-- What this item changes about `language-servers`. Folded into
     .abydos/backlog/spec/language-servers.md by `abydos-backlog done`.

     ADDED, MODIFIED and REMOVED. A rename is a REMOVED and an ADDED.
     Write each requirement as it will read in the spec, in the present
     tense — not as a description of the edit.
     The requirements already there, to name exactly:
       A tool Xcode owns comes from Xcode, not from the PATH
       One search finds every tool this program runs
       A language server is kept until the app goes, and no longer
       One server per project per server, not per language
       What is running can be seen and stopped
       A project chooses which server answers for a language
       A chosen server that cannot be started says so
       The Java debugger belongs to the server that hosts it
-->

## ADDED Requirement: Choosing where a server comes from takes effect now

Three preferences decide which server answers and where it comes from: the image
a tool comes from, which server a language uses, and the container runtime an
image is run by. Changing one of them acts on the projects that are open, at
once and without anything being reopened.

That is a stronger promise than it sounds, because a server that will not start
is deliberately not tried again — a name that is wrong is wrong every time, and
retrying it means a toast every few seconds for the rest of the session. So
everything remembered about a refusal is remembered under the conditions in
force when it was given, and a preference is exactly those conditions changing.
Until it was reconsidered, the one way back was Stop in the list of running
servers.

**A stored preference that changes nothing until something restarts is worse
than one that was not stored**, because it looks like it worked: there is no
error to read and nothing on screen disagrees with what was asked for. Somebody
who chooses an image is looking at the editor, so the server starts for the file
already open rather than for the next one — clearing the memory alone would be
the same fault with a longer fuse.

**A running server that is no longer the one being asked for is stopped**, and
that is the disruptive reading taken deliberately. A project holds one server
for a language and no more, and what the old one goes on publishing is a
toolchain the project has stopped using. The minutes a Java server spends
importing again are the cost of the choice that was just made, paid while
somebody is looking at the thing they changed.

Only what the change is about. A project whose own `.abydos/tools.json` answers
the question is untouched when the setting behind it moves, and choosing an
image for one tool leaves every other project's servers alone. A project worked
on inside its own devcontainer takes its servers from in there, so an image
named out here is not a change to anything it does — but which server answers
for a language is still its question.

A value on its way to being a value is not a choice. Picking "Custom image"
writes an empty image before anybody has typed a name, and an empty image means
the tool installed here, so nothing is stopped or started until there is a name
to start.

### Scenario: an image chosen for a server that has already failed

- **Given** a Rust project whose `rust-analyzer` exits on startup, so nothing is
  running for it
- **When** Settings ▸ Tools ▸ Rust — rust-analyzer is set to a container image
- **Then** the server starts from that image without the project being reopened
- **And** the file already open is announced to it

### Scenario: a project that changes which server answers

- **Given** a Java project with `jdtls` running
- **When** Settings ▸ Tools ▸ Language servers points Java at the other server
- **Then** `jdtls` is stopped
- **And** the other server is what is asked for, and says so plainly if it
  cannot be started

### Scenario: a runtime that can run a container

- **Given** a server whose image could not be fetched because the chosen
  container runtime is not running
- **When** a runtime that is running is chosen instead
- **Then** the image is fetched and the server starts

### Scenario: a project that pins its own answer

- **Given** a project whose `.abydos/tools.json` names the image for a tool
- **When** the setting for that tool is changed to something else
- **Then** the project's server is neither stopped nor restarted

## MODIFIED Requirement: A language server is kept until the app goes, and no longer

A server started for a project is not stopped when its window closes, when the
window is torn off, or when the project is switched away from. Coming back to a
project would otherwise pay for its index all over again, and an editor that
goes quiet for a minute whenever somebody changes project is worse than the
memory a spare server holds.

It is stopped when Abydos itself goes, by every way it goes — including the
command-line modes, which call `exit` and run no delegate method.

And it is stopped when it is no longer the server being asked for: by hand, from
the list of what is running, or because a preference changed which server
answers for its language or where it comes from. Those are the only two reasons,
and both are somebody saying so — neither is the app deciding a server has been
idle long enough.

Two windows on one checkout hold one server between them, whichever way the path
is spelled.

### Scenario: switching project and coming back

- **Given** a project with a running server
- **When** the window is switched to another project and back
- **Then** it is the same server process as before, and nothing has re-indexed

### Scenario: the app exits

- **Given** two projects, each with a running server
- **When** the app exits, however it exits
- **Then** neither server is still running afterwards

### Scenario: the server it is running is no longer the one asked for

- **Given** a project with a running server
- **When** a preference is changed so that another server, or the same one from
  somewhere else, is what the project asks for
- **Then** the running one is stopped and what is asked for is started
