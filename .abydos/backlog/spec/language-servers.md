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

## Requirement: One server per project per server, not per language

A project holds one running copy of each *server*, not one per language id. One
program answers for several languages — clangd for `c`, `cpp` and `objc`;
typescript-language-server for four — so a table keyed by the language started a
second copy of the same program the first time somebody opened a `.cpp` beside a
`.c`, each indexing the same compilation database.

### Scenario: two languages one server answers for

- **Given** a project with a `.c` and a `.cpp` file
- **When** both are opened
- **Then** one `clangd` is running for that project, not two

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
