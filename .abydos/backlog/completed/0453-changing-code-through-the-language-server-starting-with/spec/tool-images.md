<!-- What this item changes about `tool-images`. The one requirement it
     touches was written while the containers were built, for a message this
     program had never sent — 0453 is the first thing to send one, and the
     scenario at the end is that sentence driven rather than assumed. -->

## MODIFIED Requirement: A server in a container talks about files by their names on this machine

A language server started from an image sees the project at a mount inside the
container and knows no other name for it. Everything it is sent names files as
this machine names them, everything it says names them the same way, and the
translation happens at the edge of the client in both directions — for the URIs
that are values and for the ones that are keys, so that a workspace edit's map of
changes crosses too.

A path the container cannot see is refused rather than guessed at: inventing a
name inside a mount would point the server at the wrong file rather than at
none. Where a server has named directories beyond the project, those are the
other things it can see, and a file in one of them crosses in both directions
exactly as a file in the project does. Everything else is still refused, which
is the same rule over a longer list rather than a weaker one.

### Scenario: a diagnostic about an open file

- **Given** a project mounted at `/workspace` in a container
- **When** the server reports a problem in `file:///workspace/main.go`
- **Then** it is reported against the file's path on this machine

### Scenario: going to a declaration

- **Given** the same project, and a call to a function declared in the same file
- **When** the declaration is asked for
- **Then** the place that comes back is a file on this machine

### Scenario: a declaration in a directory the server named

- **Given** a server given a dependency cache from this machine beside the
  project
- **When** it answers with a file in that cache
- **Then** the place that comes back is that file's path on this machine

### Scenario: a file in neither

- **Given** the same server
- **When** it is asked about a file that is in neither the project nor anything
  it named
- **Then** nothing is translated, and the server is told about no such file

### Scenario: a rename crossing in both directions

- **Given** a project in a container, and a symbol used in two of its files
- **When** it is renamed
- **Then** every file the answer names is a file on this machine
- **And** both are changed
