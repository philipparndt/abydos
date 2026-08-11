## MODIFIED Requirement: A server in a container talks about files by their names on this machine

A language server started from an image sees the project at a mount inside the
container and knows no other name for it. Everything it is sent names files as
this machine names them, everything it says names them the same way, and the
translation happens at the edge of the client in both directions — for the URIs
that are values and for the ones that are keys, so that a workspace edit's map
of changes crosses too.

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

## ADDED Requirement: A server may say it reads directories the project does not contain

Almost every language server is answered by the project alone, and is given the
project alone. One is not: a server with no classpath finds a library's source
by walking the caches a build tool left behind — `~/.m2/repository` and
`~/.gradle/caches` — so the same server in a container with one mount indexes
the project perfectly and answers nothing at every dependency boundary.

So a server may name the directories it reads outside the project, and they are
mounted for it. It is a list per server rather than a rule for all of them,
because what one reads is a fact about that server: another server's cache is a
saving where this one's is the answer, and one that resolves its dependencies by
running a build tool is hindered by being handed a read-only copy of them.

What is mounted is what was named — a cache, not the directory above it that
holds the credentials — and it is read-only unless the server writes there. The
writable case is a server's own scratch, and it is mounted precisely because
what it writes there has to be readable from this side: a file unpacked out of a
jar inside the container and named back to the editor would be an answer that
opens nothing.

A directory that is not on this machine is an ordinary machine and not a broken
one. A read-only one that is missing is not mounted, and the server then
truthfully reports no dependencies; a writable one is created, since it is the
server's scratch rather than somebody's cache.

### Scenario: a dependency's source in the local repository

- **Given** a Java project naming a server that reads `~/.m2/repository`
- **And** a dependency whose source jar is in it
- **When** the declaration of a type from that dependency is asked for
- **Then** the place that comes back is a file this machine can open

### Scenario: a machine that has never run that build tool

- **Given** the same project on a machine with no `~/.m2`
- **When** the server is started
- **Then** it starts, with no repository mounted and none created

### Scenario: what a server may do to a cache

- **Given** a server given a dependency cache from this machine
- **When** it runs
- **Then** it can read it and cannot write to it

## MODIFIED Requirement: A published image is only offered once somebody has run it

The published images offered for a tool are the ones that have been built,
pushed, fetched back out of the registry and driven against a real project.
Listing one nobody has run would be exactly the failure the list exists to
prevent — a name offered as known-good that is not — so a tool nobody has done
that for offers no published image at all. It may still offer the recipe this
app ships, which is a different claim: that is a build, and what it produces is
whatever the Dockerfile says today.

Beside the choice, for whoever names their own, is what an image has to do: the
tool on the entry point so that it is what runs, speaking the protocol on
standard input and output with nothing printed before the first header, the
project readable at the mount, and everything else it needs inside the image,
because nothing else on this machine is visible from in there — save the
directories that server has named, which are mounted where it says they go, and
which an image that looks elsewhere for will find empty without saying so.

Where an offered image carries a tag that moves, the label says so, since a
list of images known to work is a claim with a date on it when the name is
mutable.

### Scenario: a server nobody has published an image for

- **Given** a language server this editor knows about and has no known-good
  published image for
- **When** its image is chosen in settings
- **Then** no published image is among the choices

### Scenario: an image named by hand

- **Given** a tool whose image is a name somebody typed
- **When** that tool's settings are looked at
- **Then** what the image has to provide is written there
