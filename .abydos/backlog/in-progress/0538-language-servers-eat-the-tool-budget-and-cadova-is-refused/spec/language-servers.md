## ADDED Requirement: Keeping a server costs no other tool its turn

Every subprocess this app starts is registered so that the app going ends it —
a child is handed to launchd rather than killed with its parent, so nothing else
would. Two kinds are registered, and they are counted differently.

The **short** ones are a diagram render, a diagram export and a Cadova build:
started, watched against a deadline of their own, let go of when they end. No
more than twelve of those run at once. It is a backstop against a runaway — every
render starting a container that hangs, thirty seconds apart, for an afternoon —
rather than a budget anybody is meant to feel, and twelve outstanding at one
moment is twelve that are not coming back.

The **long** ones are the language servers, one per project per server, kept for
the session by design. They are counted against nothing: a server is not a tool
somebody is waiting on, and refusing to start a build because a project has a
dozen servers open answers a question nobody asked. Both kinds are ended when
the app ends, by every way it ends.

A tool refused by the cap is told what is holding the slots — how many of each
kind of work is outstanding — and nothing else. In particular a tool that was
never started from an image is never described as one, and the container runtime
is only named where every one of the outstanding tools is in fact in a
container, which is the only case where a runtime that has stopped answering
explains it.

### Scenario: a project of several languages opening a Cadova preview

- **Given** a session holding a dozen language servers and no tool running
- **When** a Cadova model is opened
- **Then** the build starts

### Scenario: the app goes with both kinds running

- **Given** a session holding language servers and diagram renders at once
- **When** the app exits, however it exits
- **Then** none of either kind is still running

### Scenario: a build refused with nothing in a container

- **Given** twelve Cadova builds outstanding, none of them from an image
- **When** another model is opened
- **Then** the pane says twelve builds are already running and none has
  finished, and says nothing about images or about a container runtime

### Scenario: a render refused with everything in a container

- **Given** twelve diagram renders outstanding, every one of them from an image
- **When** another diagram is opened
- **Then** the pane names the twelve renders and says that a container runtime
  which has stopped answering is the usual reason
