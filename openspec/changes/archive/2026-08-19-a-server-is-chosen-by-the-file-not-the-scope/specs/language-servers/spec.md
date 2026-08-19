## ADDED Requirements

### Requirement: The server asked about a file is the one whose root owns it

A file's language server SHALL be found from the file: the nearest ancestor
directory holding that language's root markers, stopping at the project. It SHALL
NOT be chosen from whichever subproject is currently scoped.

Every question is affected, not only navigation — completion, hover,
diagnostics, rename and usages are all asked of the same server. Following
`Stadium` out of `cadova-models/Sources/HexKeyHolder/main.swift` did nothing at
all while the scope was `go-service`: the search for a root started at
`go-service` and walked *downward*, found no `Package.swift`, and started no
Swift server. Silence, and nothing in the log, because nothing had gone wrong —
nobody had asked for a Swift server in a Go module.

**The scope keeps everything else.** Which launch configurations there are, which
module a build runs in, which tree git acts on: unchanged. Which server knows
about a file is a question about the file.

**Nearest ancestor wins**, so a package inside a package answers for its own
files. A file belonging to no subproject falls back to the project root, which is
what every file does today.

#### Scenario: a file from another subproject

- **GIVEN** a checkout holding `cadova-models` with a `Package.swift` and
  `go-service` with a `go.mod`
- **AND** the scope set to `go-service`
- **WHEN** a symbol in `cadova-models/Sources/HexKeyHolder/main.swift` is
  followed
- **THEN** the Swift server rooted at `cadova-models` answers, and the jump
  happens

#### Scenario: one of several modules of the same language

- **GIVEN** three Go modules in one checkout and no subproject scoped
- **WHEN** a file in the third is asked about
- **THEN** the server rooted at *that* module answers, rather than whichever
  module was found first

#### Scenario: a repository that is one project

- **GIVEN** a checkout with a single manifest at its root
- **WHEN** any file in it is asked about
- **THEN** the answer is what it was before this change

### Requirement: A file is opened against the server it is asked about

The root a file is registered with SHALL be the root every later question about
it uses. A file opened under one root and asked about under another reaches a
server that has never been told the file exists, which is indistinguishable from
having no server at all — the fault this replaces.

So the root SHALL be worked out once, when the file is opened, and carried with
it. No caller may reach for the scope to ask a question about a file.

#### Scenario: opening and then asking

- **WHEN** a file is opened and then asked for a definition, a completion, a
  hover and a rename
- **THEN** every one of those reaches the server the file was registered with

#### Scenario: the scope changes while a file is open

- **GIVEN** an open file whose server is rooted at its own subproject
- **WHEN** the scope is switched to another subproject
- **THEN** the file's questions still reach the same server

### Requirement: A server starts for a subproject only when a file needs it

A server SHALL NOT be started for a subproject nobody has opened a file from.
Starting one per subproject at launch would cost minutes of the machine for
questions nobody has asked: sourcekit-lsp needed an index build of 651 files and
about two minutes before its first useful answer in one Cadova package, measured
on this machine.

Where somebody does work across several subprojects, one server per language per
subproject is the cost, and it is paid only for the ones being read.

#### Scenario: a checkout of eight subprojects

- **WHEN** it is opened and one Swift file is read
- **THEN** one Swift server is running, rooted at that file's package

#### Scenario: a second subproject of the same language

- **WHEN** a file from a second Swift package is opened
- **THEN** a second Swift server starts, rooted at that package, and the first
  keeps answering about its own files
