## ADDED Requirement: The Swift indexer builds outside the project, and stands outside it too

sourcekit-lsp builds the package in order to index it, and by default it builds
into the package's own `.build` — the directory a terminal build uses. Two
builds in one directory take turns holding SwiftPM's lock and invalidate each
other's work: measured on this machine, a nine-second incremental build took ten
minutes while the indexer had the directory. So the server is given a scratch
path of its own, beside the caches at
`~/Library/Caches/abydos/index/<project>-<hash>`, one per project and the same
one every time — derived data, thrown away at any time, and not one more thing
to add to an ignore file or to search by accident.

The same is true of where the server is *started*. A build the server runs may
be handed an output path with no directory in it — a compiler temporary — and a
relative path is written wherever the process happens to stand. Started in the
project, that is thousands of untracked files in somebody's checkout: 1424 of
them on the day this was found, four per source file of the package being
prepared. So the Swift server's working directory is the scratch path as well.
Which project it is for does not depend on that: the root is named absolutely,
in the initialize request and on the command line.

Every other server is started in the project, which is right for it: nothing
else here builds the project in order to answer a question.

### Scenario: the indexer is told where to build

- **Given** a Swift project
- **When** its language server is started
- **Then** the command line carries a scratch path outside the project
- **And** the same project is given the same scratch path every time, and two
  projects of the same name are given different ones

### Scenario: a build the indexer starts writes a relative path

- **Given** a Swift project whose server has been started
- **When** a build beneath that server writes a file whose path has no directory
  in it
- **Then** the file appears under the project's scratch path
- **And** the project's own directory is unchanged

### Scenario: a server that does not build the project

- **Given** a Go project, or a Java one
- **When** its language server is started
- **Then** it is started in the project
