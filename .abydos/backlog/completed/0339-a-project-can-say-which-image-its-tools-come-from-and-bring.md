# A project can say which image its tools come from, and bring them with it

`b73ba0edb` · 2026-08-07

Every project needs tools installed before it can be worked on: a language
server in the version it expects, a renderer, a build tool — on every machine
anybody uses, kept in step with everybody else's. A checkout that names its
own images needs none of that.

`.abydos/tools.json` says which image provides which tool, and it is checked
in, because what draws a diagram in this repository is the repository's
business. Settings say the same thing for one person across every project —
somebody who would rather not install a Java toolchain at all. The file wins
where both speak: a personal default must not change how a checked-in diagram
looks.

PlantUML is the first, and the shape it settles is the one the rest will use.
An image that was asked for beats a local install, which is the point of
asking: pinning a version is how the same file comes to look the same on two
machines. Where no image is named, whatever is on the machine is used, and
where there is neither, the pane says what to install.

Apple's `container` is preferred over docker because it needs no daemon
running before it will answer, and any docker-compatible command line will do
— docker, nerdctl, podman all take the three flags this needs. A render is
`run --rm -i`: the diagram arrives on standard input and the picture leaves
on standard output, so the container never sees the project at all. A tool
that does need the project — a language server will — gets it mounted, and
read-only where it has no business writing.

A render now has a deadline. That came out of trying it here: a runtime that
is installed but whose service is not running accepts the command and answers
nothing, and a preview that spins for ever says nothing about why. It now
names the command it is running while it waits, and names it again when it
gives up.

Not verified end to end: no container runtime on this machine will start —
Apple's apiserver registers with launchd and exits, and the docker daemon is
not running — so the picture has never come back through an image here. The
command lines are covered by tests; the running of them is not.
