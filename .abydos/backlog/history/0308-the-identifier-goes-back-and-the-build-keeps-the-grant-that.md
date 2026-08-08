# The identifier goes back, and the build keeps the grant that goes with it

`5bc82d0d8` · 2026-08-06

Switching the bundle identifier back is half of it. macOS files the Local
Network grant against the executable's *UUID*, not against the identifier
alone, and the linker derives that from content — so every rebuild lost the
grant again, which `make run` would hit as surely as `make install`. Measured
rather than assumed: the same binary, same identifier, denied; with its UUID
patched to one that is already associated, reachable.

So a local build pins the UUID before signing, and everything the app starts
keeps the network. `PIN_UUID=0` turns it off and `make release` sets it,
because identical UUIDs make crash reports ambiguous about which build
produced them — the reason the linker derives it from content in the first
place. Releasing by hand is refused if the pinned UUID is still there.

The App Store rename is what left the grant behind, and this beta cannot
create a new one: the prompt goes through nehelper, which refuses
UserEventAgent the connection that presents it. When that is fixed, the
identifier can move again and both of these come out.
