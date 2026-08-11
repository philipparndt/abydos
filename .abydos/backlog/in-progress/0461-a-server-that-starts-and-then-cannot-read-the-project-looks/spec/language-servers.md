## ADDED Requirement: A server that started and is not answering says so above the file

Everything else this program knows about a server's health is about *starting*
one: it is installed or it is not, its image is here or it is being fetched, the
handshake was answered or it was not. A server that starts, answers the
handshake and then cannot make sense of what it was pointed at is in none of
those states, and the strip above the file went away the moment the client was
running — so a project the server could not read looked exactly like one where
everything worked, until somebody opened the outline and found it empty.

It is not one server's problem. jdtls with a classpath it could not resolve,
gopls outside a module, clangd with no `compile_commands.json` and rust-analyzer
against a toolchain the image has not got all start, all answer the handshake,
and all then know nothing.

So the strip has a third thing to say, beside "install this" and "this is on its
way": **what the server said about itself since it started**, in the server's own
words behind a button that says so. Three ways in and one sentence each — it is
running and has reported a problem; it is running and could not answer either;
it is not running at all, because it exited on the way up or because its image
never arrived. **None of them reads as a crash**: two say the server is running,
all three name the project rather than the server, and the next project this
server is asked about may be perfectly readable.

**An error message on its own is not enough to call a server broken.** Servers
log errors that are not fatal, and measured on the `rust-analyzer` image this
repository builds, the levels do not sort them: a project it could not load is
reported as a *warning*, and `duplicate DidOpenTextDocument`, which costs
nothing, as an *error*. So a message puts the server's own words on screen as a
report and no more; the stronger sentence — it cannot read this project — waits
for a question it could not answer as well. **Any answer with content in it takes
both back**, which is what a server that grumbled and went on working does
within seconds.

What the empty symbol palette says is unchanged and stops being the first
anybody hears it.

### Scenario: a server that exits because the project pins a toolchain it has not got

- **Given** a Rust project whose `rust-toolchain.toml` names a toolchain the
  server's image does not carry
- **When** a file in it is opened
- **Then** the strip above the file says `rust-analyzer` is not running for this
  project
- **And** its details are the server's own words — the toolchain, the file that
  named it, and where the rest of the log is

### Scenario: a server that complains and goes on working

- **Given** a project whose server reports a problem at error level and then
  answers questions about the file normally
- **When** the file is open
- **Then** nothing is said above it

### Scenario: a server that says it cannot work and then cannot answer

- **Given** a running server that has reported a problem with the project
- **When** a question is put to it and comes back empty or fails
- **Then** the strip says it is running and cannot read this project

### Scenario: what one project's server said is not said about another

- **Given** two projects in the same language, one whose server cannot read it
  and one whose server is fine
- **When** a file in each is opened
- **Then** only the first has anything above it

## MODIFIED Requirement: Choosing where a server comes from takes effect now

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

**What a running server said about the project is remembered the same way and
forgotten with the rest.** A server that started and cannot read the project is
exactly the state somebody fixes by choosing another image, another server, or a
runtime that works — and what it said was said about a toolchain that is no
longer the one being asked for. Left behind, the strip above the file would go
on reporting a refusal from a server that has since been replaced.

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
- **And** what the old server said about the project is no longer above the file

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
