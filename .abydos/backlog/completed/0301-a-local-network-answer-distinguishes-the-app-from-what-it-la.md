# A local network answer distinguishes the app from what it launches

`8f579c4e7` · 2026-08-06

The permission belongs to the app, and a program the app starts inherits
whatever answer the app has. When it has none, what the program reports is
"no route to host" — an error about a network that is working fine.

So the probe asks twice: once through Network.framework, as the app, and
once through a plain socket, as a child does. Two answers rather than one
is the difference between "this app was never granted the permission" and
"the grant does not reach what it launches", which are otherwise the same
sentence. Launched from the Dock there is no stdout to read it in, so the
report is written to the diagnostic log as well as printed.

Refused now passes for the app as it already did for the child: something
answered, which cannot happen unless the connection was allowed.

The development bundle signs with the hardened runtime, as the release has
all along — signature-dependent failures should reproduce in what you run.
