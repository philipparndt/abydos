# A build can carry the identifier this app used to have

`a8bd1d848` · 2026-08-06

macOS files the Local Network grant under the bundle identifier and has no
way to carry one from an app's old name to its new one. The rename to
de.rnd7.ideai for the App Store therefore left the permission behind on
dev.philipparndt.ideai, where it still is.

That normally costs nothing, because a renamed app is asked about again. It
cost something here: the prompt is presented by UserEventAgent through
nehelper, and on macOS 27 beta nehelper refuses it the connection, so every
request defaults to denied and no dialog appears for any app without a
grant. The denial is inherited by everything the app launches, which is how
a debugger reports "connect: no route to host" about a broker that is up.

BUNDLE_ID builds under the old identifier and inherits the grant that still
works — a workaround for a machine, not a change to what ships. Release
refuses to sign anything that is not the shipping identifier, since an
exported BUNDLE_ID would otherwise reach it, and a release under a name that
is not the app's takes every grant and update on a user's machine with it.
