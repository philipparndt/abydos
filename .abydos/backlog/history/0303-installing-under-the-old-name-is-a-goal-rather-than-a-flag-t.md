# Installing under the old name is a goal rather than a flag to remember

`0a2826734` · 2026-08-06

The Local Network grant lives on the identifier this app had before the App
Store rename, and macOS cannot move one from an app's old name to its new
one. On macOS 27 beta it cannot be granted afresh either — the prompt goes
through nehelper, which refuses UserEventAgent the connection that shows it.

`make install-legacy` is that install. It matters that it has a name: the
flag it replaces is silent when forgotten, and what a plain `make install`
produces then is an app whose debugger reports "connect: no route to host"
about a broker that is up. Nothing about it reads as a wrong build.

Releases keep the shipping identifier, which Scripts/release.sh enforces.
