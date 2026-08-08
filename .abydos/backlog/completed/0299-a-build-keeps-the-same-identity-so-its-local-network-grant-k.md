# A build keeps the same identity, so its Local Network grant keeps applying

`d71c859ff` · 2026-08-05

An ad-hoc signature has no team: its identity is the code directory hash, which
is different after every build. macOS keys the Local Network grant on the
signing identity, so the permission granted to yesterday's build matched
nothing today — and because the denial is inherited by everything the app
spawns, a debugger or a program under test lost the LAN with EHOSTUNREACH,
which reads as "connect: no route to host" and points nowhere near a
permission. `tccutil` cannot reset LocalNetwork, so the only way back was the
System Settings pane, by hand, after every build.

Signed with the Apple Development certificate when there is one, which keeps
the identity stable across rebuilds, and says so when there is not.

And the usage description the prompt needs: without it macOS has nothing to
show and on some releases never asks at all.
