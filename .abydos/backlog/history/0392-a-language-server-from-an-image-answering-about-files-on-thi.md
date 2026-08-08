# A language server from an image, answering about files on this machine

`ec5730010` · 2026-08-08

The last part of running a tool from a container, and the part that had to
be right: the launch, and the paths.

The launch is small, as expected. `LanguageServers.resolve` now takes the
image a project named and hands back either the copy installed here or a
container with the project mounted at /workspace, started where the manifest
is — which is not always the mount, since a repository commonly keeps its
go.mod a level down. No arguments are added on this side: the contract an
image is held to puts the server on the entry point with whatever flags it
needs, so anything sent after that would be read as a file to open.

The paths are the work. Every `file:` URI is rewritten at the edge of
`LSPClient`, on the way out and on the way back, over the whole message
rather than at each place that sends one — a URI turns up in more shapes
than anybody can keep a list of, and a list that misses one goes wrong
silently rather than loudly. Keys as well as values, because a workspace
edit is a map keyed by URI and a walk that looked only at values would bring
every edit home and leave the file it belongs to on the other side.

Two things that are not paths and would fail the same way: the editor's
process id is not sent to a container, where that number means nothing and a
server watching it finds no such process and exits during the handshake; and
jdtls is no longer told about JDKs and bundles on this machine, which name
nothing inside an image that has to carry its own.

The image is fetched before the first start rather than at it, since that is
minutes the first time. Nothing waits on the main thread for it: what was
opened meanwhile is kept and sent when the server comes up, or the server
would start knowing about no documents at all — running, answering the
handshake, and saying nothing about the file in front of somebody.

And there is now an image that has actually been run. `ToolImages/gopls`
builds gopls on the Go base image, because gopls is a front end for a
toolchain and one without `go` beside it starts, shakes hands and then knows
nothing about any symbol. `ContainerLSPLiveTests` drives it end to end —
diagnostics, document symbols, and a go-to-declaration — and asserts that
every one of them names a path on this machine rather than /workspace. That
is the whole feature in one test, and it is skipped where the image is not
built.

Still not listed as known-good in the catalogue: that list means somebody
can pull it, and this one is not published yet. Backlog 390 says what is
left — publishing it, the other five servers, and a page per tool.
