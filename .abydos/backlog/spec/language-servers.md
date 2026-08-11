# Language servers

Completion, problems, go-to-declaration and find-usages come from a language
server: a separate program, none of them bundled and none installed on
anybody's behalf, because the copy already on the machine — the one matching
the compiler actually being used — is nearly always the right one. This page is
about which copy that turns out to be, how long it lives, how many of it there
are, and how somebody sees what is running and stops one.

## Requirement: A tool Xcode owns comes from Xcode, not from the PATH

`sourcekit-lsp`, `clangd` and `lldb-dap` are asked of the selected Xcode —
`xcrun --find` — before the `PATH` is looked at at all. Each of the three is
also shipped by every Swift toolchain manager, and a manager's directory comes
before the system's on a login shell's `PATH`, so the search that started there
found a release older than the SDK the build uses.

That costs more than processor time: the build runs one Swift and the
diagnostics on screen come from another, and a red squiggle the compiler
disagrees with is worse than a slow machine, because it is believed.

Only those three. Everything else — gopls, rust-analyzer, pyright — belongs to
its own language's toolchain, and asking `xcrun` for one would find nothing and
be a slower way of finding nothing. The answer is remembered for the life of the
process, including "Xcode has no such tool", because `xcrun` is a process and
this is asked every time something wants to know whether a server is installed.

### Scenario: a toolchain manager's copy is first on the PATH

- **Given** `~/.swiftly/bin/sourcekit-lsp` is earlier on the `PATH` than
  Xcode's
- **When** a Swift file is opened and a server is started for it
- **Then** the running server's own executable is Xcode's, under
  `…/XcodeDefault.xctoolchain/usr/bin/sourcekit-lsp`

### Scenario: a server Xcode does not ship

- **Given** `gopls`, which no Xcode contains
- **When** it is looked for
- **Then** Xcode is not asked, and it is found the ordinary way

## Requirement: One search finds every tool this program runs

There is one list of directories, and everything that looks for a command-line
tool uses it: the language servers, the debug adapters, the container runtime,
tmux, the assistants. Three sources in this order — the `PATH` this process was
given, so a `PATH` somebody set deliberately still chooses the tool; then the
`PATH` their login shell has, which is where a version manager puts things and
the only source that keeps up with them; then a floor of well-known directories
for when the shell cannot be asked.

The middle source is the one that matters in practice. An app launched from the
Finder has `PATH=/usr/bin:/bin:/usr/sbin:/sbin` and nothing else, so without it
everything works from a terminal and nothing works from the Dock.

Two searches is the failure this replaces: a tool a version manager owns was
found by whichever half asked the shell, and a tool that exists in two places
was a different program depending on which half looked for it.

### Scenario: a tool only the login shell knows about

- **Given** an app whose own `PATH` is the Finder's four directories, and a
  tool that lives only where a version manager put it
- **When** any part of the program looks for that tool
- **Then** it is found, at the path the person's own shell would give

### Scenario: the same tool in two places

- **Given** a tool present both in a well-known directory and earlier on the
  login shell's `PATH`
- **When** the program runs it, and somebody runs it in a terminal pane beside
  it
- **Then** both are the same file

## Requirement: A language server is kept until the app goes, and no longer

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

## Requirement: One server per project per server, not per language

A project holds one running copy of each *server*, not one per language id. One
program answers for several languages — clangd for `c`, `cpp` and `objc`;
typescript-language-server for four — so a table keyed by the language started a
second copy of the same program the first time somebody opened a `.cpp` beside a
`.c`, each indexing the same compilation database.

A server is filed under its own name, which is what makes that hold once a
language has more than one server to have: two Java servers are two entries and
not one, so changing which one the project asks for does not find the one that
was running before. A server that was asked for and could not be started keeps
an entry under the name that was asked for, so what is remembered about the
refusal is not remembered about the server that was never chosen.

### Scenario: two languages one server answers for

- **Given** a project with a `.c` and a `.cpp` file
- **When** both are opened
- **Then** one `clangd` is running for that project, not two

### Scenario: a project that changes which server it wants

- **Given** a project whose file names one of two servers for a language
- **When** it names the other instead
- **Then** the two are held apart, and the second does not find the first's
  entry

## Requirement: What is running can be seen and stopped

View ▸ Running Servers and Containers lists the language servers and containers
this app has started and has not ended, and every row has a Stop. It is what
makes keeping a server until the app quits an affordable decision rather than a
leak: a session that has collected nine of them is visible without anybody
running `ps`.

It is also where the footer's chip leads. Somebody who has just read which server
is answering for their file has four questions next — is it really running, what
is it costing, which executable did the system resolve, and how do I stop it —
and this window is the one place all four are answered.

A row's memory is the process **and everything it started**, with the count of
processes beside it, because the server is not where the weight is — measured on
one repository, `sourcekit-lsp` alone reads 32.7 MB and the same server with the
three processes underneath it reads 410.8 MB. A row also says which executable
the operating system resolved, which is how the toolchain requirement above
stays true where somebody can see it.

Beside the project a row names, a server somebody *chose* says which language it
was chosen for and where the choice was written. It is the one place a project's
choice can be seen rather than inferred — the settings page knows no project —
and the person reading it is exactly the one wondering why the server running is
the one they are paying for.

**A jdtls started for the debugger alone has a row of its own**, saying that is
what it is there for. Nobody chose it and nothing on screen would otherwise
account for it, and it is the largest thing in the list: a JVM importing a
reactor. This is where its memory is read and where it is stopped.

A server running inside the project's devcontainer says where it lives and
gives no number, since its client out here is a few megabytes and the container
below it is a row of its own. Stopping a server that has a container of its own
stops the container; stopping a server inside the project's devcontainer does
not, because that container is the project's and holds somebody's terminal.

The list is read when somebody looks at it — opening it, bringing it to the
front, pressing Refresh, stopping something — and never on a timer, because
asking a container runtime for memory costs about a second of its attention.

### Scenario: stopping a server, and needing it again

- **Given** a running server in the list
- **When** its Stop is pressed
- **Then** the row goes, and the process is no longer running
- **And** when a file needs that server again it starts, and the list has a row
  for it

### Scenario: a server in the project's devcontainer

- **Given** a project worked in its devcontainer, with a server running inside
- **Then** the server's row says which container it is in and gives no memory
- **And** the container has a row of its own, with the memory on it

### Scenario: a server the project chose

- **Given** a project whose `.abydos/tools.json` names the server for a language
- **When** that server is running and the list is read
- **Then** its row says the language it was chosen for and that the choice came
  from `.abydos/tools.json`

### Scenario: the jdtls a debugging session started

- **Given** a project whose editing server hosts no adapter, and a debugging
  session started in it
- **When** the list is read
- **Then** there is a row for jdtls saying it is there for the debugger
- **And** its Stop ends it

### Scenario: arriving from the footer

- **Given** a file whose footer names the server answering for it
- **When** the footer's chip is clicked
- **Then** this list opens, with a row for that server

## Requirement: A project chooses which server answers for a language

A language may have more than one server, and which of them is right depends on
the project rather than on the machine. Java is the case: one server reads the
build file for the classpath and costs a JVM and most of two gigabytes, and
another is instant, needs no JVM, and answers syntactically only. Neither is
wrong; they answer different questions, and only the person with the project
knows which they are asking.

So the project says, in the file that already says where its tools come from:

    { "languages": { "java": "kmp-lsp" } }

Under a name of its own rather than at the top level of `.abydos/tools.json`,
because the keys up there are tool names and these are language ids, and
`plantuml` is already both — a renderer that comes from an image and a language
a server answers for. Which server, and where that server comes from, are two
questions, and the file keeps them two.

Settings say the same thing for one person across every project, under
Tools ▸ Language servers, which lists every language and the servers there are
for it. **Where the two disagree the file wins and the setting is the default**,
which is the rule 0424 settled for a diagram's theme: a checked-in answer is a
statement about the project, and a personal preference that quietly overrode it
would mean two people on one repository being answered by two different
programs.

**Where there is a choice to make, each candidate says what it costs**, in a line
beside the two names. Two bare names say what the options are called and nothing
about which one anybody should pick, and the difference between these two is
minutes and gigabytes against knowing that a call has the wrong argument type. A
language with one server carries no such line, because it offers no trade.

Nothing is chosen from the build files. A `pom.xml` would select the server that
reads poms, which is exactly wrong for the person whose reason for wanting the
fast one is that the slow one hurts on the project the pom describes.

Not two at once, either: two servers *answering about one file* means two sets of
diagnostics and no rule for which wins, so a project holds the chosen one and only
the chosen one. What that rules out is a second opinion about the code, and not a
second process — the jdtls a debugging session starts answers about no file at
all.

### Scenario: a project names a server for a language

- **Given** a Java project whose `.abydos/tools.json` names a server for `java`
- **When** a `.java` file in it is opened
- **Then** the server that starts is the one named
- **And** the row for it in Running Servers and Containers says which language
  it was chosen for and that the choice came from `.abydos/tools.json`

### Scenario: the file and the setting disagree

- **Given** a setting naming one server for a language
- **And** a project whose `.abydos/tools.json` names another for the same one
- **When** a file of that language is opened
- **Then** the server named in the project's file is the one that runs

### Scenario: only the chosen one starts

- **Given** two servers that both answer for a language, and a project that
  shows the root markers of both
- **When** the project's servers are started
- **Then** one server runs for that language, the one chosen

### Scenario: choosing between two servers

- **Given** a language with two servers to choose between
- **When** the settings page is read
- **Then** each of them says in one line what it costs and what it buys
- **And** a language with one server says only that it is the only one

## Requirement: A chosen server that cannot be started says so

A server the project asked for and that this app cannot start is a sentence, and
never the other server started quietly in its place. Somebody who chose the
instant server and was given the one that costs two gigabytes would have no way
to tell from the editor, and would spend the afternoon looking for the fault in
a server that is not running.

Three ways of not being startable, and all three say the same thing in different
words: no server of that name exists; a server of that name exists but answers
for another language; or it is the right server, is not installed here, and has
no image named for it. Each says what was asked for, where it was asked for —
the project's file or the settings page — what there is instead, and that
nothing has been started in its place.

The first two are said out loud once per project, because they are a sentence
somebody wrote themselves and can fix. The third keeps the quieter treatment an
uninstalled server has always had, since half the projects on a machine touch a
language whose server nobody installed.

### Scenario: a server nobody has

- **Given** a project whose `.abydos/tools.json` names a Java server this app
  does not know
- **When** a `.java` file in it is opened
- **Then** the strip above the file says that server was asked for and is not
  here
- **And** its details name the server this app does have for Java, and say that
  nothing has been started in its place
- **And** no other Java server is running for that project

### Scenario: a server that answers for another language

- **Given** a project that names `gopls` for `java`
- **When** a `.java` file in it is opened
- **Then** what is said names `gopls` and says it answers for Go rather than
  for Java

## Requirement: Choosing where a server comes from takes effect now

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

## Requirement: The footer says which server is answering, and from where

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

## Requirement: A server that started and is not answering says so above the file

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

## Requirement: A server can change the code, and rename is what it is asked for

Everything else this program asks a language server is a question. Renaming a
symbol is the first thing it asks that changes files, and it changes many of
them at once: the answer is a *workspace edit*, and one of those from a real
project arrives about a hundred files in six directories, none of which anybody
had open.

Rename ▸ from the code's context menu, or ⇧F6, which is IDEA's. **The new name
is typed where the old one is** — a field laid over the symbol, in the text,
scrolling with it — rather than in a dialog. It is the navigator's in-place
rename on a row, one layer in: the thing being renamed is on screen, the new
name goes where the old one is, and the rest of the window carries on. Return
takes it, Escape drops it, clicking away takes it, and a name that is refused
leaves the field standing with the text still in it, because a name that is not
allowed is a typo far more often than it is a change of mind.

### Scenario: renaming a symbol used in several files

- **Given** a project with a server running, and a symbol used in three files of
  which one is open
- **When** it is renamed from the editor
- **Then** all three files say the new name
- **And** the open one says it in its editor as well as on disk

### Scenario: the caret is not on anything renameable

- **Given** the caret on a bracket
- **When** a rename is asked for
- **Then** nothing is said and no field appears

## Requirement: A rename that cannot be offered is not offered

An offer that fails is worse than an absence. Whether renaming is possible is
settled before anything appears on screen, from two different sources and in
this order: **what the server said it can do at the handshake**, which is a fact
about the server, and then **`prepareRename`**, which is a fact about the
position. A server that does not rename is never asked.

Three ways of not being able to, and only one of them is said out loud. No
server running for the file is silent, because that is most files in most
projects and what there is to say about a missing server is the strip above it.
The server's own "nothing here" is silent, because that is what the caret being
on a bracket looks like every time. **A server that is running and does not
rename says so, by name**, because that is a fact about the server somebody
chose and they can choose another.

`prepareRename` is asked only of servers that say they support it. Several
servers rename and answer `MethodNotFound` to that question, which arrives as a
refusal indistinguishable from a symbol that cannot be renamed; for those, the
word under the caret is what the field opens on, which is the answer the editor
had before it asked anything.

### Scenario: a server that does not rename

- **Given** a running server whose capabilities do not offer rename
- **When** a rename is asked for
- **Then** it says that server does not rename, and names it
- **And** no field appears

### Scenario: a server that renames but is not asked first

- **Given** a running server that renames and does not offer `prepareRename`
- **When** a rename is asked for with the caret in a word
- **Then** the field opens on that word

## Requirement: A rename says which kind of rename it is

A language may have more than one server and they do not know the code the same
way. One reads types; another matches names over what it indexed. For a question
that is a trade somebody made on purpose — a wrong answer costs a keystroke. For
an answer that *changes forty files*, it is the one thing they need to know
before they accept it, and 0449 made it possible for a project to be pointed at
such a server without the person at the editor knowing.

So a rename offered by a server that reads text rather than types says so, under
the field, **before the name is typed**. A warning that arrives with the result
is a warning about something that has already happened, and a rename is undoable
where somebody's confidence in the tool is not.

### Scenario: a project pointed at the syntactic Java server

- **Given** a Java project whose `.abydos/tools.json` chooses the server that
  matches names rather than types
- **When** a symbol in it is renamed
- **Then** the field says that unrelated things of the same name will be renamed
  too, and says it before the name is typed

## Requirement: A workspace edit is worked out in full before anything is written

A workspace edit is not one change, it is forty, and the failure that matters is
twenty files written and the twenty-first refused — which leaves a project that
compiles nowhere and no record of how it got there. The answer is in three
layers, and the first is by far the most important.

**Everything is read, edited and checked while nothing has been written.** A
file that is not there, a range the file does not have, two edits over one
character, a rename onto a name something already holds: all of them are known
before anything is touched. **One refusal and nothing happens at all** — the
person is told which file and why, their project is exactly as it was, and they
can fix that one thing and ask again. Half a refactoring is not a lesser good
than a whole one, it is worse than none.

**A write that fails anyway is put back**, from the previous contents worked out
in the first step — which is the same information the undo entry holds, so the
rollback and ⌘Z are one mechanism rather than two that can come to disagree.

**A rollback that cannot finish names every file on both sides**, by name and
not by count. It is the floor, it takes the file system refusing twice, and when
it happens being exact is the only thing left worth doing.

An edit this program cannot read in full is refused in full. An entry of a kind
it has never heard of, dropped quietly, would apply most of somebody's
refactoring and leave the rest — which is the halfway state all of this exists
to avoid.

### Scenario: one file of forty cannot be written

- **Given** a rename that would change forty files, one of which is read-only
- **When** it is applied
- **Then** nothing is changed at all, and it says which file stopped it

### Scenario: a file that changed under the server

- **Given** a rename whose edits name a place the file no longer has
- **When** it is applied
- **Then** it says the server and the file no longer agree about that file
- **And** no other file in the edit is changed

## Requirement: A workspace edit reaches open documents through the rope, and files that move

A file with an editor on it cannot be written behind the editor's back: the
buffer and the disk would then say different things, and whichever was saved
next would win. So an open document is read from its buffer and changed through
it — one replacement of the whole file, so its share of the undo is one entry
and not one per edit the server sent — and then saved, and the server is told.
Everything else is read and written without an editor being made for it, which
is what a rename across five hundred bundles needs.

A workspace edit can also create, move and delete files, which is how renaming a
Java class moves `Foo.java` to `Bar.java`. A file that moves and is open has its
tab closed before the move and reopened under the new name afterwards, or the
next auto-save would put the buffer back at the path the move had just emptied.
The order the server sent its changes in is kept, because it is meaningful:
edits before a move and edits after one both happen, and mean the same thing.

### Scenario: renaming a Java class

- **Given** a Java class in a file of its own, and another file that uses it
- **When** the class is renamed
- **Then** both files say the new name
- **And** the file holding the class has the new name too

### Scenario: a file that is open in two panes

- **Given** a file open in two editor panes and changed by a rename
- **When** the rename is applied
- **Then** both panes show the new text

## Requirement: A whole rename is one undo

A rename that touched forty files and is undone forty times is not an undo. One
⌘Z takes the whole of it back — every file's text, every file that moved, every
file that went — and the Edit menu names it after the new name so that what it
will take back is legible before it is pressed.

It is on the same stack as what the tree does to files, and that is the only
place it can be: a document's own history knows nothing of the other thirty-nine,
and a rename that moved a file is not a text edit at all.

While a name is being typed, ⌘Z belongs to the field and takes back the typing.

### Scenario: undoing a rename across three files

- **Given** a rename that changed three files
- **When** ⌘Z is pressed once
- **Then** all three say what they said before

### Scenario: undoing a rename that moved a file

- **Given** a rename that moved `Foo.java` to `Bar.java`
- **When** it is undone
- **Then** the file is back under its old name with its old text

## Requirement: A server that declines after offering is named

The two gates in front of a rename — the server's capabilities, then
`prepareRename` — cannot catch a server that passes both and then answers the
rename itself with nothing. kmp-lsp 0.25.0 did exactly that for every Java
symbol: it said it renamed, agreed there was a `Greeting` at that position, and
answered the rename with `null`.

Nothing was renamed, and that much has to be said, because a name was typed and
accepted and the code did not change. **What is said names the server**, which
is the only thing that distinguishes this from a caret on a comma. By this point
the caret was not on a comma: the server itself picked the symbol out and gave
back its extent, so "the server found nothing to change" describes the one
possibility that has been ruled out. Which server declined is a fact about
something somebody chose in `.abydos/tools.json` and can choose differently.

It is said as information rather than as an error. Nothing changed and nothing
is broken — a server declining is not a server failing, and the two do not
deserve the same colour.

### Scenario: a server that advertises rename and then declines

- **Given** a running server that renames, which answered `prepareRename` with a
  range
- **When** a new name is typed and accepted, and the server answers with no edit
- **Then** it says nothing was renamed, and names the server that declined
- **And** it says it as information rather than as a failure

## Requirement: Debugging Java does not depend on which server edits it

The Java debug adapter is an Eclipse bundle loaded *inside* jdtls rather than a
program beside it — so it needs a jdtls, and it needs one that has imported the
project, because a launch is a class and a classpath and the import is what
computes the classpath. What it does **not** need is for jdtls to be the server
answering about files. A project that chose the fast syntactic server for
editing, because its five hundred bundles take minutes and gigabytes to import,
gets a jdtls started for the debugger alone.

**Started when somebody presses Debug, and not before.** Importing at every
project open would be instant debugging paid for by every session that never
debugs, which is most of them and is exactly the cost the fast server was chosen
to avoid. So the first Debug of a session waits, and **says what it is waiting
for** while it does: how long it has been, and what the server itself last said
about how far it has got. A wait that says nothing is indistinguishable from a
debugger that has hung.

**It answers nothing about any file.** The chosen server answers about files and
this one answers two questions about the project — where the adapter is listening,
and what the classpath is. It is not in the table that requests and open
documents are routed through, it is never told a document is open, and the
compilation problems jdtls reports for everything it imports reach nothing. Two
servers over one file with two sets of diagnostics and no rule for which wins is
still refused; this is not that.

**A project whose Java server is jdtls already debugs through the server it has.**
Nothing starts a second jdtls beside a jdtls: the one that is running has the
import, and a second would spend the minutes again for the same answer and hold a
second copy of it. And should the project's choice move to a server that hosts
the adapter, the one started for the debugger is stopped, since what it holds is
then a gigabyte of nothing.

**A project worked on inside its own devcontainer still has no Java debugger**,
and now says so. The bundle is a path on this machine and the JVM would be this
machine's, so what got debugged would be a different toolchain from the one the
project builds with — which is the whole reason a devcontainer's servers live in
there.

**Nothing is launched on a classpath that is not this project's.** Three ways a
classpath is not one, and all three used to end in a JVM dying of something that
read as the project's fault:

- The server answers about **its own fallback workspace** rather than about this
  project, which is what it does until the import has finished. A well-formed
  answer for the wrong thing, and taken at face value it compiles against whatever
  the newest toolchain on the machine is and then fails on the class file version.
  So an answer counts only when it is *about* the project.
- The classpath names directories the server **has not compiled into yet**, since
  it fills them after the import. So the project is compiled before the JVM
  starts.
- The server answers, at once and for ever, that there **is no classpath** — which
  is what an OSGi bundle gets, its dependencies being a target platform rather
  than anything in its build file. That is an answer and not a wait, and it is
  said as one: nothing is started, and nobody is left watching a spinner for
  something that has already happened.

### Scenario: a classpath the server has not worked out yet

- **Given** a Java project whose server has not finished importing it
- **When** a class in it is debugged
- **Then** no JVM is started on the classpath the server answers with meanwhile
- **And** what is being waited for is said, until the answer is about this project

### Scenario: a project whose classpath the server cannot report

- **Given** an OSGi bundle, whose dependencies are in its manifest rather than in
  its build file
- **When** a class in it is debugged
- **Then** it says the server reports no classpath, and that this is its answer
  rather than a wait
- **And** no JVM is started

### Scenario: debugging a project whose editing server is the syntactic one

- **Given** a Java project whose `.abydos/tools.json` chooses the server that
  hosts no debug adapter
- **When** a class in it is debugged
- **Then** jdtls is started for the debugger alone and the session runs
- **And** while it is waited for, what is being waited for is said, with how long
  it has been

### Scenario: what the debugger's server is asked

- **Given** a debugging session running through a jdtls started for the debugger
- **When** a file in the project is opened, edited and asked about
- **Then** that server is told nothing about it and is asked nothing about it
- **And** nothing it says about any file appears anywhere

### Scenario: the editing server already hosts the adapter

- **Given** a Java project whose server is jdtls, running and importing finished
- **When** a class in it is debugged
- **Then** the session goes through that server and no second one is started

### Scenario: a project worked on in its devcontainer

- **Given** a Java project whose servers run inside its own devcontainer
- **When** a class in it is debugged
- **Then** it says the debugger is a bundle loaded into a jdtls on this machine,
  and that working on this machine is what it would take

## Requirement: A project or a person can name the executable for a server

Which server answers for a language and where it comes from are two questions
this project already answered. A third had no answer: *which program* is the
server. Every route from a tool's name to a process goes through a search of the
path, and that is the step that fails when a toolchain manager owns the name — the
name is then a proxy that resolves the project's pinned toolchain and refuses to
run a server that toolchain has not got, rather than running the one installed
beside it. Every toolchain manager that puts shims on the path has this shape.

So a path can be named, in the project's own file and in settings, under the
server's name beside its image. A command containing a separator is taken as a
path and is not searched for: something named and absent is nothing, and a name
substituted for it would be exactly the program that was being avoided, arriving
silently. `~` is expanded where the path is this machine's; where the server runs
from a container the path is the container's and is passed through untouched,
because expanding it here would send one machine's home directory into an image.

The project's file wins and the setting is the default, as it does for the image
and for the choice of server — but key by key rather than entry by entry, since
what is said about a server under one name is several independent things and a
project adding one of them must not take away another that a person set for every
project.

A named path with nothing at it is its own sentence above the file, naming which
of the two places named it. Not the install hint, which would be false twice:
something was named, and installing the tool under its own name is what produced
the proxy in the first place.

### Scenario: a project naming a path

- **Given** a project naming an executable for a server
- **And** an executable file at that path
- **When** a file that server answers for is opened
- **Then** that is the program started, and no path is searched

### Scenario: a name that is a toolchain manager's proxy

- **Given** a project whose pinned toolchain has no such server in it
- **And** an executable named for the server, from another toolchain
- **When** a file in it is opened
- **Then** the server reads the project, resolving the compiler and the standard
  library through the pin as it should

### Scenario: a path with nothing at it

- **Given** a project naming an executable that is not there
- **When** a file that server answers for is opened
- **Then** the strip says what was named and where it was named, and no server
  is started in its place

### Scenario: a person's default and a project's answer

- **Given** a person who has named an executable for a server
- **When** a project names one too
- **Then** the project's is used
- **And** where the project says only what to tell the server, the person's
  executable still stands

## Requirement: A project can say what to tell a server when it starts

What a server is told in its initialize request used to be a table in this
repository, which meant one server was configured and the rest were told nothing.
A setting a project needs cannot live here: a path into a toolchain only that
machine has is not something this repository can know.

So a project can say it, under the server's name, and it is merged over whatever
would have been sent — all the way down rather than at the top level, so a
project adding one setting to a server this app already configures keeps the rest
of it. A server the table says nothing about can be told things too, which is the
only way most of them could be configured at all.

Values are passed through as they were written. Unlike the executable, nothing
here is known to be a path, so nothing is expanded — a server that wants an
absolute path must be given one.

### Scenario: a server the table configures

- **Given** a project adding one setting for a server that is already configured
- **When** it starts
- **Then** it is sent that setting, and everything it was sent before

### Scenario: a server the table says nothing about

- **Given** a project naming settings for such a server
- **When** it starts
- **Then** it is sent them, where before it was sent nothing at all
