## ADDED Requirement: A project or a person can name the executable for a server

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

## ADDED Requirement: A project can say what to tell a server when it starts

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
