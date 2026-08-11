<!-- What this item changes about `language-servers`. Folded into
     .abydos/backlog/spec/language-servers.md by `abydos-backlog done`. -->

## REMOVED Requirement: The Java debugger belongs to the server that hosts it

It said that a project whose Java server is a different one has no adapter at
all. It has one: jdtls is started for the debugger alone, and the debugger no
longer goes with the choice of editing server. Replaced by the requirement below,
which is a rename as well as a rewrite.

## ADDED Requirement: Debugging Java does not depend on which server edits it

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

## MODIFIED Requirement: What is running can be seen and stopped

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

## MODIFIED Requirement: A project chooses which server answers for a language

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
