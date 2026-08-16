<!-- 0501. Two MODIFIED and no ADDED, and that is the choice rather than the
     default. What the chip says lives in the footer requirement, and an ADDED
     beside it would leave "the three are three because they are three
     different waits" standing as a true sentence about a chip that now has
     four words. The rule for reading what a server says about itself lives in
     0461's requirement, and an ADDED beside that one would leave two rules
     disagreeing about the same message. Both are the drift a delta exists to
     prevent, so both requirements are rewritten whole. -->

## MODIFIED Requirement: The footer says which server is answering, and from where

Beside the caret's position and the language, the editor's footer names the
language server answering for the file in front of somebody — and says where
that server came from, which is the half that was missing. An installed copy, an
image and the project's own devcontainer are three different answers, and the
first is the one people assume: a Rust project pointed at an image that started,
initialised and answered was indistinguishable from nothing having happened, and
the only places that knew were the container runtime, `lsp.log`, and a window
somebody has to go and open.

The copy installed here is named and no more. A server from an image is named
with the container mark the titlebar's pill already wears and then the image, in
full, because which image is exactly what somebody wants to know and is written
nowhere else on screen. A server inside the project's devcontainer wears the mark
and stops there: the container is a fact about the window, the pill already names
it, and repeating it under every file would be the same word over and over.

A server on its way says so in one word — fetching, building, starting — and the
three are three because they are three different waits: the network, this
machine's compiler for a couple of minutes, and the project's container coming
up. The words agree with the strip above the file because both are written in one
place.

**A fourth word, for a server that is here and not ready: preparing.** The other
three are a server that has not arrived; this is one that arrived, answered the
handshake, and is building what the project depends on before it can answer
anything true about it. Measured on a Swift package with C++ in its dependencies
and nothing built, the server publishes `No such module` thirteen seconds after
the file is opened and withdraws it a minute later, and for that minute the chip
said the same word it says when every answer is right. Nothing is hidden while it
says this — the errors stay exactly where they are — and the tool tip says the
part the word cannot: that an error here saying something does not exist may be
about the build rather than about the code.

It is in the footer and nowhere else, and the number that decided that is 1.2
seconds — what preparing costs on a *second* open with everything already built.
A banner appearing and vanishing inside a second and a half on every project open
would push the file down and let it back for nothing, while the chip is already
drawn during preparation and only changes its word.

**What counts as preparing is the work the server says it is doing**, over
work-done progress, which is the protocol's own and not any one language's:
`sourcekit-lsp` opens a token before the false error appears and closes it after
it clears, `gopls` opens one numbered `Setting up workspace`, `rust-analyzer`
opens seven named ones. Only the *first* stretch of work counts — servers report
progress for as long as they run, and a chip that said preparing after every save
is a chip people stop reading — and a stretch is not over the moment nothing is
open, because several servers close each step before opening the next.

**And it is quiet when there is nothing to name.** A language with no server
running and none coming gets no chip at all, which is most files in most
projects; a footer that talks about every one of them is a footer people stop
reading, and what there is to say about a *missing* server is the strip above the
file, which has room for the sentence and for the way to fix it.

**A name that fits is drawn however short it is.** The chip is what gives way
when the editor is narrow, and it gives way in two stages: it is cut at the tail
first, and dropped entirely when what is left would be too little to read — a
chip saying `ru…` says nothing anybody can use, and what it crowds out is where
the caret is. That floor is a claim about the *room*, never about the name: a
server called `gopls` is a third the width of one called `rust-analyzer` and
wants none of the room the rule is about, and a bar wide enough for a long name
is wide enough for a short one.

Clicking it opens the list of what is running. That is where the questions the
chip raises are answered — whether it is really running, what it costs, which
executable was resolved, and how to stop it — and it is not the settings page,
which is where the answer is changed but which knows no project.

**What it says is pushed to it, never asked for while drawing.** The footer is
redrawn every time the caret moves and draws the position in the same view, so it
holds the words and works nothing out; the words are worked out when a server
starts, stops, is refused or is reconsidered, which the app already announces.

### Scenario: a server answering from an image

- **Given** a Rust project whose `.abydos/tools.json` names an image for
  `rust-analyzer`
- **When** a `.rs` file in it is opened and the server is answering
- **Then** the footer names `rust-analyzer`, the container mark, and the image
- **And** the strip above the file says nothing, because nothing is wrong

### Scenario: a server in the project's devcontainer

- **Given** a project worked in its devcontainer, with a server running inside
- **When** a file it answers for is open
- **Then** the footer names the server and the container mark, and does not
  repeat the container's name, which the titlebar's pill is already showing

### Scenario: a short name in a wide editor

- **Given** a Go project whose `go.mod` is in a subdirectory, with `gopls`
  installed on this machine and answering
- **When** a `.go` file in it is open in an editor the width of a window
- **Then** the footer reads `gopls` and nothing else, beside the position and
  the language
- **And** it is not dropped for being short: what may drop it is the room it has,
  not how much of that room it wants

### Scenario: a chip with nowhere to go

- **Given** a server whose name and image together are wider than the bar's
  remaining space
- **When** what is left would be too few characters to read
- **Then** no chip is drawn at all, and the language and the caret's position
  keep their place

### Scenario: a server building what the project depends on

- **Given** a Swift package whose dependencies have not been built
- **When** a file in it is opened and the server reports the work it is doing
- **Then** the footer reads `sourcekit-lsp — preparing`
- **And** the diagnostics on the file are shown exactly as the server sent them,
  including the one about a module that does not exist yet
- **And** nothing is said above the file

### Scenario: the same package opened a second time

- **Given** the same package with everything already built
- **When** a file in it is opened
- **Then** the chip says preparing for the second or so the server takes, and
  then names the server and no more

### Scenario: a server that goes on working after it is ready

- **Given** a server that has finished preparing and reports progress again —
  a reindex after a save, a check of the file
- **When** that work begins
- **Then** the chip does not say preparing again: the wait it names happens once
  per server

### Scenario: a file whose language has no server

- **Given** a file of a language nothing is running for and nothing is coming
  for
- **Then** the footer says where the caret is and what the language is, and
  nothing about a server

### Scenario: a server on its way

- **Given** a server whose image is being fetched
- **When** a file it will answer for is open
- **Then** the footer says the server is fetching
- **And** it says the same thing the strip above the file says

### Scenario: the caret moves

- **Given** a file with a server answering for it
- **When** the caret is moved
- **Then** nothing is looked up to draw the footer: what it says was settled when
  the server's state last changed


## MODIFIED Requirement: A server that started and is not answering says so above the file

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

**Nothing a server says while it is preparing counts at all.** A server that has
to build the project before it can answer reports the failures of its own build
at error level — `sourcekit-lsp` runs a compiler per target and an indexing
process per file, and says `Finished with exit code 1` about the ones that do not
come back cleanly — and it answers hover and completion with nothing for the same
minute. Those are both halves of the rule below, and both of them false: measured
on a package with nothing built, twenty seconds into an ordinary first open the
strip said the server could not read the project and a toast said it again, about
a server that answered thirty seconds later. So while a server is preparing its
error-level messages are logged and no more, and an empty answer is not counted
against it — an answer *with* content still is, because that is what withdraws a
sentence and there is no case for holding good news back. Nothing is lost: the
state is untouched, and a server that really cannot read the project says so
again once it is ready and is believed then.

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

**Where something else already knows the reason, it says it instead.** A project
pinning a toolchain the image has not got is read before anything is started and
answered with what would read it, which is a better sentence than the server's
complaint about it; this is the state for everything that cannot be known ahead
of the server trying.

### Scenario: a server that exited on the way up

- **Given** a server that started and then exited before answering the handshake
- **When** a file it would have answered for is opened
- **Then** the strip above the file says it is not running for this project
- **And** its details are the server's own words and where the rest of the log is
- **And** it is not started again for that project until something changes

### Scenario: a pin, which is known before the server is asked

- **Given** a Rust project whose `rust-toolchain.toml` names a toolchain the
  server's image does not carry
- **When** a file in it is opened
- **Then** the strip says what could read the project, rather than quoting the
  server's complaint about it

### Scenario: a server complaining about its own build while it prepares

- **Given** a Swift package whose dependencies are not built, whose server
  reports the non-zero exits of its own index build at error level
- **When** a file in it is opened and hover and completion come back empty
- **Then** nothing is said above the file and no toast is shown
- **And** the footer says the server is preparing, which is what is true

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
