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
-->

## ADDED Requirement: A project chooses which server answers for a language

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

## ADDED Requirement: A chosen server that cannot be started says so

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

## MODIFIED Requirement: One server per project per server, not per language

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

## MODIFIED Requirement: What is running can be seen and stopped

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

## ADDED Requirement: The Java debugger belongs to the server that hosts it

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
