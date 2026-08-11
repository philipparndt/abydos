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

Nothing is chosen from the build files. A `pom.xml` would select the server that
reads poms, which is exactly wrong for the person whose reason for wanting the
fast one is that the slow one hurts on the project the pom describes.

Not two at once, either. Two servers for one language means two sets of
diagnostics over one file and no rule for which wins, so a project holds the
chosen one and only the chosen one.

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

## Requirement: The Java debugger belongs to the server that hosts it

Debugging Java goes through the Java language server, because the debug adapter
is a bundle loaded inside it rather than a program beside it. A project whose
Java server is a different one has no adapter at all, however well that server
reads the code, and is told so as the consequence of a choice — which is what it
is — rather than being left with a Debug button that does nothing.

### Scenario: debugging with a Java server that hosts no adapter

- **Given** a project whose chosen Java server is not the one the debug bundle
  loads into
- **When** a debug session is started
- **Then** it says the debugger lives inside the other server, and names it

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
